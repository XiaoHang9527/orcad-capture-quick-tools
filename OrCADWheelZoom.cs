// OrCAD Quick Tools: plain wheel zoom and right-button grab-and-drag viewport.
// Build with build_wheel_zoom.ps1. .NET Framework 4, no extra runtime package.
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using System.Collections.Generic;
using Accessibility;

internal static class OrCADWheelZoom
{
    const int WM_MOUSEWHEEL = 0x020A, WH_MOUSE_LL = 14;
    const int WM_MOUSEMOVE = 0x0200, WM_RBUTTONDOWN = 0x0204, WM_RBUTTONUP = 0x0205;
    const int WM_HSCROLL = 0x0114, WM_VSCROLL = 0x0115;
    internal const int LiveScrollCommand = 5;
    static int capturePid;
    static string statePath, logPath;
    static bool active;
    static int stateMode;
    static IntPtr hook;
    static HookProc callback = OnMouse;
    static Process capture;
    static EventWaitHandle stop;
    static int wheelCount;
    const string Version = "wheel-0.20-signals-key-independent";
    static readonly PanGesture pan = new PanGesture();
    static IntPtr panView;
    static IntPtr panForeground;
    static POINT panStartClient, panLatest;
    static IntPtr clickReplayView, clickReplayForeground;
    static POINT clickReplayPoint;
    static DateTime clickReplayQueuedAt;
    internal static readonly UIntPtr RightClickTag = new UIntPtr(0x4F435251u);
    static bool panMovePending;
    static bool panNeedsInit;
    static ScrollAxis panHorizontal, panVertical;
    static int panCount;
    static readonly Dictionary<string, int> reasonCounts = new Dictionary<string, int>();
    static readonly Dictionary<string, string> reasonDetails = new Dictionary<string, string>();
    static int receivedWheels;
    static int timerTicks;
    static int mouseCallbacks, rawWheels, rawRightDowns, hookRearms;
    static readonly InputWatchdog inputWatchdog = new InputWatchdog();
    static DateTime lastControllerRead = DateTime.MinValue;

    internal sealed class InputWatchdog
    {
        bool initialized;
        int x, y, callbacks, misses;
        internal bool Sample(int nextX, int nextY, int nextCallbacks, bool inScope)
        {
            bool movingWithoutHook = initialized && inScope && (nextX != x || nextY != y) && nextCallbacks == callbacks;
            misses = movingWithoutHook ? misses + 1 : 0;
            initialized = true; x = nextX; y = nextY; callbacks = nextCallbacks;
            if (misses < 2) return false;
            misses = 0; return true;
        }
    }
    static readonly int[] modifierKeys = { 0x10,0x11,0x12,0x5B,0x5C,1,2,4,5,6 };

    // The original right-down is deferred until release. Small movement still
    // produces a right click; crossing the threshold starts direct viewport drag.
    internal sealed class PanGesture
    {
        internal int Mode { get; private set; } // 0 idle, 1 pending, 2 dragging, 3 cancelled
        int x, y;
        internal void Begin(int startX, int startY) { x = startX; y = startY; Mode = 1; }
        internal bool Move(int nextX, int nextY, int threshold)
        {
            if (Mode != 1 || (Math.Abs((long)nextX-x) < threshold && Math.Abs((long)nextY-y) < threshold)) return false;
            Mode = 2; return true;
        }
        internal void Cancel() { if (Mode != 0) Mode = 3; }
        internal int Release() { int result = Mode; Mode = 0; return result; }
    }

    [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] struct RECT { public int L, T, R, B; }
    [StructLayout(LayoutKind.Sequential)] struct SCROLLINFO
    { public uint Size, Mask; public int Min, Max; public uint Page; public int Pos, TrackPos; }
    sealed class ScrollAxis
    {
        internal IntPtr Owner, ScrollWindow, Control;
        internal int Bar, Message, StartPosition, LastRequested, StartClient, ClientLength;
        internal SCROLLINFO Initial;
        internal ScrollRoute Route;
        internal bool Blocked;
    }

    internal sealed class ScrollRoute
    {
        internal IntPtr Target, Control;
        internal ScrollRoute(IntPtr target, IntPtr control) { Target = target; Control = control; }
    }
    internal enum ScrollResult { Failed, Unchanged, Applied, UnexpectedPosition }
    internal enum AxisResult { Idle, Applied, Unavailable, Unsafe }
    internal delegate ScrollResult ScrollTransport(ScrollRoute route, int position);

    internal static ScrollRoute[] ScrollRoutes(IntPtr drawing, IntPtr owner, IntPtr control)
    {
        // Capture's shared scrollbar is a child of AfxMDIFrame80. The frame
        // owning that control is not necessarily the handler moving OrRandomView.
        if (drawing == owner) return new ScrollRoute[] { new ScrollRoute(drawing, control) };
        return new ScrollRoute[] { new ScrollRoute(drawing, control), new ScrollRoute(owner, control) };
    }

    internal static bool FindScrollRoute(ScrollRoute[] routes, int position, ScrollTransport send, out ScrollRoute selected)
    {
        selected = null;
        foreach (ScrollRoute route in routes) {
            ScrollResult result = send(route, position);
            if (result == ScrollResult.Applied) { selected = route; return true; }
            // Retry a different route ONLY when the position did not change.
            // Do not issue extra commands after a timeout or an unexpected jump.
            if (result != ScrollResult.Unchanged) return false;
        }
        return false;
    }

    internal static bool ScrollbarUsable(bool enabled, bool visible) { return enabled && visible; }

    internal static bool WheelBlockedByPan(int mode) { return mode == 1 || mode == 2; }

    internal static bool MouseMessageRelevant(int message, int panMode)
    {
        // Input origin is intentionally NOT a filter: remote-control, accessibility
        // and mouse-driver inputs may carry LLMHF_INJECTED. Our own PostMessage
        // forwarding never returns through this low-level hook, so no loop guard
        // based on injected-input flags is needed. Scope is checked by Eligible.
        return message == WM_MOUSEWHEEL || message == WM_RBUTTONDOWN || message == WM_RBUTTONUP || panMode != 0;
    }

    internal static bool MoveBothAxes(Func<AxisResult> horizontal, Func<AxisResult> vertical)
    {
        // A fitted/blocked horizontal axis must not stop vertical movement.
        // Only uncertainty after sending a command (timeout/wrong position) is
        // a whole-gesture stop condition.
        if (horizontal() == AxisResult.Unsafe) return false;
        return vertical() != AxisResult.Unsafe;
    }
    [StructLayout(LayoutKind.Sequential)] struct MouseData
    { public POINT Point; public uint Data, Flags, Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Sequential)] internal struct MouseInput
    { public int X, Y; public uint Data, Flags, Time; public UIntPtr Extra; }
    // MOUSEINPUT is the largest member of INPUT's native union on x86/x64.
    [StructLayout(LayoutKind.Sequential)] internal struct NativeInput
    { public uint Type; public MouseInput Mouse; }
    [StructLayout(LayoutKind.Sequential)] struct GuiInfo
    {
        public int Size; public uint Flags;
        public IntPtr Active, Focus, Capture, MenuOwner, MoveSize, Caret;
        public RECT CaretRect;
    }
    delegate IntPtr HookProc(int code, IntPtr message, IntPtr data);
    delegate bool EnumWindowProc(IntPtr window, IntPtr parameter);
    [StructLayout(LayoutKind.Sequential)] internal struct MenuBarInfo
    { public uint Size; public int L, T, R, B; public IntPtr Menu, MenuWindow; public uint Flags; }
    [StructLayout(LayoutKind.Sequential)] internal struct MenuItemInfo
    {
        public uint Size, Mask, Type, State, Id;
        public IntPtr SubMenu, CheckedBitmap, UncheckedBitmap, ItemData, Text;
        public uint TextLength; public IntPtr ItemBitmap;
    }
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowProc callback, IntPtr parameter);
    [DllImport("oleacc.dll")] static extern int AccessibleObjectFromWindow(IntPtr window, uint objectId, ref Guid interfaceId,
        [MarshalAs(UnmanagedType.Interface)] out IAccessible accessible);
    [DllImport("oleacc.dll")] static extern int AccessibleChildren(IAccessible accessible, int start, int count,
        [Out, MarshalAs(UnmanagedType.LPArray, ArraySubType=UnmanagedType.Struct, SizeParamIndex=2)] object[] children, out int obtained);
    [DllImport("user32.dll")] static extern bool GetMenuBarInfo(IntPtr window, int objectId, int item, ref MenuBarInfo info);
    [DllImport("user32.dll")] static extern int GetMenuItemCount(IntPtr menu);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool GetMenuItemInfo(IntPtr menu, uint item, bool byPosition, ref MenuItemInfo info);
    [DllImport("user32.dll", SetLastError=true)] static extern IntPtr SetWindowsHookEx(int id, HookProc proc, IntPtr module, uint thread);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr value);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr value, int code, IntPtr message, IntPtr data);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] static extern IntPtr GetModuleHandle(string name);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint thread, ref GuiInfo info);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(POINT pt);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPhysicalPoint(POINT pt);
    [DllImport("user32.dll")] static extern bool GetPhysicalCursorPos(out POINT pt);
    [DllImport("user32.dll")] static extern bool PhysicalToLogicalPointForPerMonitorDPI(IntPtr hwnd, ref POINT pt);
    [DllImport("user32.dll")] static extern bool PhysicalToLogicalPoint(IntPtr hwnd, ref POINT pt);
    [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] static extern IntPtr GetWindowDpiAwarenessContext(IntPtr hwnd);
    [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr hwnd);
    [DllImport("user32.dll")] static extern int GetDlgCtrlID(IntPtr hwnd);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd, StringBuilder text, int count);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr hwnd, uint flag);
    [DllImport("user32.dll")] static extern bool IsWindowEnabled(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll", SetLastError=true)] static extern bool GetScrollInfo(IntPtr hwnd, int bar, ref SCROLLINFO info);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr hwnd, EnumWindowProc callback, IntPtr parameter);
    [DllImport("user32.dll", EntryPoint="GetWindowLongW")] static extern int GetWindowLong(IntPtr hwnd, int index);
    [DllImport("user32.dll")] static extern bool ScreenToClient(IntPtr hwnd, ref POINT pt);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll", SetLastError=true)] static extern bool PostThreadMessage(uint thread, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll", SetLastError=true)] static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll", SetLastError=true)] static extern uint SendInput(uint count, NativeInput[] inputs, int size);
    [DllImport("user32.dll", EntryPoint="SendMessageTimeoutW", SetLastError=true)]
    static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint msg, IntPtr w, IntPtr l, uint flags, uint timeout, out UIntPtr result);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();

    static string ClassOf(IntPtr hwnd)
    { var b = new StringBuilder(256); GetClassName(hwnd, b, b.Capacity); return b.ToString(); }
    static void Log(string text)
    {
        try {
            if (File.Exists(logPath) && new FileInfo(logPath).Length > 1048576)
                File.WriteAllText(logPath, "Wheel diagnostic log restarted (1 MiB limit).\r\n");
            File.AppendAllText(logPath, DateTime.Now.ToString("s") + " " + text + Environment.NewLine);
        } catch {}
    }
    static void Status(string text)
    { try { File.WriteAllText(statePath + ".status", text); } catch {} }

    static void Record(string reason, string detail)
    {
        int count;
        reasonCounts.TryGetValue(reason, out count);
        reasonCounts[reason] = count + 1;
        reasonDetails[reason] = detail;
    }

    static string ConfigureDpi()
    {
        try {
            if (SetThreadDpiAwarenessContext(new IntPtr(-4)) != IntPtr.Zero) return "per-monitor-v2";
            if (SetThreadDpiAwarenessContext(new IntPtr(-3)) != IntPtr.Zero) return "per-monitor";
        } catch (EntryPointNotFoundException) {}
        return SetProcessDPIAware() ? "system-aware-fallback" : "existing-context";
    }

    static string WindowInfo(IntPtr hwnd)
    {
        uint pid; GetWindowThreadProcessId(hwnd, out pid);
        return hwnd.ToInt64().ToString("X") + "/pid=" + pid + "/class=" + ClassOf(hwnd) + "/id=" + GetDlgCtrlID(hwnd);
    }

    static string Ancestors(IntPtr hwnd)
    {
        var result = new StringBuilder();
        for (int i = 0; hwnd != IntPtr.Zero && i < 8; i++, hwnd = GetParent(hwnd)) {
            if (i != 0) result.Append(" <- ");
            result.Append(WindowInfo(hwnd));
        }
        return result.ToString();
    }

    static bool TargetPoint(IntPtr hwnd, POINT physical, out POINT logical)
    {
        logical = physical;
        try { return PhysicalToLogicalPointForPerMonitorDPI(hwnd, ref logical); }
        catch (EntryPointNotFoundException) { return PhysicalToLogicalPoint(hwnd, ref logical); }
    }

    internal static int StateMode(string text, bool fresh)
    {
        if (!fresh) return 0;
        text = text.Trim();
        if (text == "hover 0" || text == "hover 1") return 2;
        // Older Tcl modules retain their original focus requirement.
        return text == "1" ? 1 : 0;
    }

    internal static int RetainedStateMode(string text, bool fresh, int previous)
    {
        // Tcl may be between truncating and writing the tiny control file.
        // Keep the previous intent only within the existing freshness lease.
        if (fresh && text.Trim().Length == 0) return previous;
        return StateMode(text, fresh);
    }

    static string ReadControllerState()
    {
        // The default File.ReadAllText sharing denies a concurrent Tcl write.
        // This is an interprocess control file, so permit writing/replacement.
        using (var stream = new FileStream(statePath, FileMode.Open, FileAccess.Read,
            FileShare.ReadWrite | FileShare.Delete))
        using (var reader = new StreamReader(stream)) return reader.ReadToEnd().Trim();
    }

    internal static string ScopeReason(bool controllerLive, bool modified, uint flags, bool captured,
        bool ownWindow, bool currentPage, string className, int controlId, bool mdi, bool inside)
    {
        if (!controllerLive) return "controller-disabled-or-stale";
        if ((flags & ~1u) != 0 || captured) return "menu-dialog-or-drag";
        if (modified) return "modifier-or-button-held";
        if (!ownWindow) return "hit-outside-capture";
        // Capture 16.6 diagnostic log 693308: the focused drawing canvas is
        // OrRandomView / AFX_IDW_PANE_FIRST, not an Afx: registered class.
        // Do not accept arbitrary Afx windows (property panes can also be MFC).
        if (controlId != 0xE900 || className != "OrRandomView") return "not-capture-drawing-view";
        if (!mdi) return "not-mdi-view";
        if (!currentPage) return "not-current-page-or-query-timeout";
        if (!inside) return "outside-client-area";
        return "eligible";
    }

    internal static bool ForegroundAllowsDrawing(bool sameProcess, bool enabled,
        IntPtr foregroundRoot, IntPtr drawingRoot, IntPtr foregroundOwnerRoot,
        IntPtr drawingOwnerRoot, string foregroundRootClass)
    {
        if (!sameProcess || !enabled || foregroundRoot == IntPtr.Zero || drawingRoot == IntPtr.Zero) return false;
        if (foregroundRoot == drawingRoot) return true;
        // GA_ROOT omits ownership. Capture's embedded/owned MFC drawing frame
        // may have a different root from OrCaptureFrame after reactivation.
        // Allow its owning main frame, NOT any same-process popup/dialog.
        return foregroundOwnerRoot != IntPtr.Zero && foregroundOwnerRoot == drawingOwnerRoot
            && foregroundRootClass == "OrCaptureFrame";
    }

    static bool DrawingBelongsToForeground(IntPtr foreground, IntPtr drawing)
    {
        uint foregroundPid, drawingPid;
        GetWindowThreadProcessId(foreground, out foregroundPid);
        GetWindowThreadProcessId(drawing, out drawingPid);
        IntPtr foregroundRoot = GetAncestor(foreground, 2), drawingRoot = GetAncestor(drawing, 2);
        IntPtr foregroundOwnerRoot = GetAncestor(foreground, 3), drawingOwnerRoot = GetAncestor(drawing, 3);
        return ForegroundAllowsDrawing(foregroundPid == capturePid && drawingPid == capturePid,
            IsWindowEnabled(foreground) && IsWindowEnabled(drawing) && IsWindowEnabled(drawingRoot)
                && IsWindowEnabled(drawingOwnerRoot),
            foregroundRoot, drawingRoot, foregroundOwnerRoot, drawingOwnerRoot, ClassOf(foregroundRoot));
    }

    internal static bool NavigationWindowAllowed(int controllerMode, bool foregroundIsCapture,
        bool belongsToForeground, bool drawingIsBoundCapture, bool enabledVisible, string ownerRootClass)
    {
        if (controllerMode == 0 || !drawingIsBoundCapture || !enabledVisible) return false;
        // A foreground Capture dialog still blocks navigation behind it.
        if (foregroundIsCapture) return belongsToForeground;
        // Hover mode only: a physically hit, visible drawing may be navigated
        // without activating Capture. Legacy focus-only controllers stay strict.
        return controllerMode == 2 && ownerRootClass == "OrCaptureFrame";
    }

    static bool DrawingNavigationAllowed(IntPtr foreground, IntPtr drawing)
    {
        uint foregroundPid, drawingPid;
        GetWindowThreadProcessId(foreground, out foregroundPid);
        GetWindowThreadProcessId(drawing, out drawingPid);
        IntPtr root = GetAncestor(drawing, 2), ownerRoot = GetAncestor(drawing, 3);
        bool available = IsWindow(drawing) && IsWindowEnabled(drawing) && IsWindowVisible(drawing)
            && IsWindowEnabled(root) && IsWindowEnabled(ownerRoot) && IsWindowVisible(ownerRoot);
        return NavigationWindowAllowed(stateMode, foregroundPid == capturePid,
            foregroundPid == capturePid && DrawingBelongsToForeground(foreground, drawing),
            drawingPid == capturePid, available, ClassOf(ownerRoot));
    }

    internal static int WheelParameter(uint data) { return unchecked((int)(data & 0xFFFF0000u)) | 0x0008; }
    internal static int PointParameter(int x, int y)
    {
        if (x < Int16.MinValue || x > Int16.MaxValue || y < Int16.MinValue || y > Int16.MaxValue)
            throw new ArgumentOutOfRangeException("point", "Mouse message coordinates exceed signed 16-bit range.");
        return (x & 0xFFFF) | ((y & 0xFFFF) << 16);
    }

    internal static int GrabPosition(int start, int min, int max, uint page, int clientLength, long delta)
    {
        if (clientLength <= 0 || max < min) throw new ArgumentOutOfRangeException("scroll geometry");
        long limit = Math.Max((long)min, (long)max - (page > 0 ? (long)page - 1 : 0));
        // Page is the visible viewport expressed in scrollbar units. Convert
        // logical client pixels to those units; subtract so the sheet follows
        // the pointer (not the opposite direction like scrolling a wheel).
        double scale = page > 0 ? (double)page / clientLength : 1.0;
        double position = start - delta * scale;
        return (int)Math.Max(min, Math.Min(limit, Math.Round(position, MidpointRounding.AwayFromZero)));
    }

    internal static int ScrollParameter(int position, int command)
    {
        // WM_*SCROLL packs only 16 position bits. Never silently wrap a large
        // position, or pre-set a thumb without moving Capture's actual view.
        if (position < 0 || position > UInt16.MaxValue) throw new ArgumentOutOfRangeException("scroll position");
        return unchecked((position << 16) | command);
    }

    // Hover mode: controller heartbeat + exact drawing class + active MDI page.
    // No titles, net names, page numbers or screen coordinates are hard-coded.
    internal static bool ScopeInputBlocks(int key, bool rightDown, bool signalsRequest)
    {
        if (rightDown && key == 2) return false;
        // Signals has its own gesture guard. A user-configurable shortcut may
        // still hold Ctrl/Shift/Alt/Win here; never loosen wheel/pan protection.
        return !signalsRequest || key == 1 || key == 2 || key == 4 || key == 5 || key == 6;
    }

    static bool Eligible(POINT pt, out IntPtr view, out POINT messagePoint, bool rightDown = false, bool signalsRequest = false)
    {
        view = IntPtr.Zero;
        messagePoint = pt;
        IntPtr top = GetForegroundWindow();
        uint pid;
        uint thread = GetWindowThreadProcessId(top, out pid);
        // MSLLHOOKSTRUCT.pt uses per-monitor-aware screen coordinates.
        // Do not guess a scale, substitute the focus HWND, or search behind another app.
        IntPtr hit = WindowFromPhysicalPoint(pt);
        IntPtr legacyHit = WindowFromPoint(pt);
        uint hitPid; uint hitThread = GetWindowThreadProcessId(hit, out hitPid);
        bool background = pid != capturePid;
        bool ownWindow = hit != IntPtr.Zero && DrawingNavigationAllowed(top, hit);
        if (background && !ownWindow) {
            Record("inactive-hover-rejected", "foreground=" + WindowInfo(top) + " hit=" + WindowInfo(hit)
                + " stateMode=" + stateMode); return false;
        }
        if (!background && !IsWindowEnabled(top)) { Record("disabled-frame", ""); return false; }
        // Query Capture's input queue when it is inactive, not the other app's
        // focus/menu flags. No focus changes or synthetic left clicks are needed.
        if (background) thread = hitThread;
        var gui = new GuiInfo(); gui.Size = Marshal.SizeOf(gui);
        if (!GetGUIThreadInfo(thread, ref gui)) { Record("gui-query-failed", ""); return false; }
        bool modified = false;
        foreach (int key in modifierKeys) {
            if (!ScopeInputBlocks(key, rightDown, signalsRequest)) continue;
            if (GetAsyncKeyState(key) < 0) { modified = true; break; }
        }
        bool mdi = false;
        IntPtr mdiClient = IntPtr.Zero, mdiChild = hit;
        IntPtr parent = GetParent(hit);
        for (int i = 0; parent != IntPtr.Zero && parent != top && i < 16; i++, parent = GetParent(parent))
        {
            if (ClassOf(parent) == "MDIClient") { mdi = true; mdiClient = parent; break; }
            mdiChild = parent;
        }
        bool currentPage = false;
        string mdiQuery = "not-queried";
        if (stateMode == 2 && mdi && hitPid == capturePid && ClassOf(hit) == "OrRandomView"
            && !modified && (gui.Flags & ~1u) == 0 && gui.Capture == IntPtr.Zero)
        {
            // Ask the MDI client for its active child, without stealing focus or
            // clicking the drawing. Bound the wait so a busy Capture stays usable.
            UIntPtr result;
            if (SendMessageTimeout(mdiClient, 0x0229, IntPtr.Zero, IntPtr.Zero, 0x23, 30, out result) != IntPtr.Zero)
            {
                ulong childValue = IntPtr.Size == 4 ? unchecked((uint)mdiChild.ToInt32()) : unchecked((ulong)mdiChild.ToInt64());
                currentPage = result.ToUInt64() == childValue;
                mdiQuery = "active=" + result.ToUInt64().ToString("X") + "/hover=" + childValue.ToString("X");
            }
            else { mdiQuery = "timeout-or-failed"; }
        }
        else if (stateMode == 1) { currentPage = active && hit == gui.Focus; }

        // Client rectangle and ScreenToClient must be queried in the target's DPI
        // context, not by mixing Capture logical units with hook physical units.
        bool converted = TargetPoint(hit, pt, out messagePoint);
        bool inside = false;
        IntPtr oldDpi = IntPtr.Zero;
        try {
            try { oldDpi = SetThreadDpiAwarenessContext(GetWindowDpiAwarenessContext(hit)); }
            catch (EntryPointNotFoundException) {}
            RECT r; POINT local = messagePoint;
            if (converted && GetClientRect(hit, out r) && ScreenToClient(hit, ref local))
                inside = local.X >= r.L && local.X < r.R && local.Y >= r.T && local.Y < r.B;
        } finally { if (oldDpi != IntPtr.Zero) SetThreadDpiAwarenessContext(oldDpi); }

        string reason = ScopeReason(stateMode != 0, modified, gui.Flags, gui.Capture != IntPtr.Zero,
            ownWindow,
            currentPage, ClassOf(hit), GetDlgCtrlID(hit), mdi, inside);
        POINT cursor; bool cursorKnown = GetPhysicalCursorPos(out cursor);
        string detail = "eventPhysical=" + pt.X + "," + pt.Y
            + " cursorPhysical=" + (cursorKnown ? cursor.X + "," + cursor.Y : "unknown")
            + " targetLogical=" + messagePoint.X + "," + messagePoint.Y
            + " converted=" + converted + " tclActive=" + active + " stateMode=" + stateMode + " flags=" + gui.Flags
            + " backgroundHover=" + background
            + " mdiQuery=" + mdiQuery
            + " foreground=" + WindowInfo(top) + " foregroundRoot=" + WindowInfo(GetAncestor(top, 2))
            + " foregroundOwnerRoot=" + WindowInfo(GetAncestor(top, 3))
            + " drawingRoot=" + WindowInfo(GetAncestor(hit, 2)) + " drawingOwnerRoot=" + WindowInfo(GetAncestor(hit, 3))
            + " capture=" + WindowInfo(gui.Capture)
            + " hit=" + WindowInfo(hit) + " legacyHit=" + WindowInfo(legacyHit)
            + " focus=" + WindowInfo(gui.Focus) + " ancestors=" + Ancestors(hit);
        Record(reason, detail);
        if (reason != "eligible") return false;
        view = hit; return true;
    }

    static bool ClientPoint(IntPtr view, POINT physical, bool clamp, out POINT client)
    {
        if (!TargetPoint(view, physical, out client)) return false;
        IntPtr oldDpi = IntPtr.Zero;
        try {
            try { oldDpi = SetThreadDpiAwarenessContext(GetWindowDpiAwarenessContext(view)); }
            catch (EntryPointNotFoundException) {}
            RECT r;
            if (!ScreenToClient(view, ref client) || !GetClientRect(view, out r) || r.R <= r.L || r.B <= r.T) return false;
            if (clamp) {
                client.X = Math.Max(r.L, Math.Min(r.R - 1, client.X));
                client.Y = Math.Max(r.T, Math.Min(r.B - 1, client.Y));
            }
            return client.X >= r.L && client.X < r.R && client.Y >= r.T && client.Y < r.B;
        } finally { if (oldDpi != IntPtr.Zero) SetThreadDpiAwarenessContext(oldDpi); }
    }

    internal static bool IsOwnRightClick(int message, UIntPtr extra)
    {
        // Only our specifically tagged right-button pair bypasses gesture
        // handling. Other injected/remote-control inputs remain supported.
        return extra == RightClickTag && (message == WM_RBUTTONDOWN || message == WM_RBUTTONUP);
    }

    internal static NativeInput[] RightClickInputs(bool releaseOnly)
    {
        var release = new NativeInput { Mouse = new MouseInput { Flags = 0x10, Extra = RightClickTag } };
        if (releaseOnly) return new NativeInput[] { release };
        var press = new NativeInput { Mouse = new MouseInput { Flags = 0x08, Extra = RightClickTag } };
        // No MOVE/ABSOLUTE flag or coordinates: Windows uses the real cursor
        // and supplies native message-position/DPI metadata to Capture.
        return new NativeInput[] { press, release };
    }

    internal static bool ReplayRightClick(Func<NativeInput[], uint> send, out uint inserted, out uint cleanup)
    {
        inserted = send(RightClickInputs(false)); cleanup = 0;
        // A partially inserted down must be paired with an up, never another
        // full click. A blocked call must not fall back to the shifted messages.
        if (inserted == 1) cleanup = send(RightClickInputs(true));
        return inserted == 2;
    }

    internal static bool ClickReplayStillCurrent(int x, int y, int currentX, int currentY, double ageMs, int gestureMode)
    {
        return gestureMode == 0 && ageMs >= 0 && ageMs <= 250
            && Math.Abs((long)currentX - x) < 6 && Math.Abs((long)currentY - y) < 6;
    }

    static void FlushRightClick()
    {
        IntPtr view = clickReplayView, foreground = clickReplayForeground;
        if (view == IntPtr.Zero) return;
        clickReplayView = IntPtr.Zero; // Consume once, including failures.
        POINT cursor;
        if (!GetPhysicalCursorPos(out cursor)
            || !ClickReplayStillCurrent(clickReplayPoint.X, clickReplayPoint.Y, cursor.X, cursor.Y,
                (DateTime.UtcNow - clickReplayQueuedAt).TotalMilliseconds, pan.Mode)
            || !PointerTargetValid(view, foreground, cursor, false)) {
            Record("pan-right-click-cancelled", "cursor/scope/gesture changed before replay"); return;
        }
        IntPtr currentView; POINT logical;
        if (!Eligible(cursor, out currentView, out logical) || currentView != view) {
            Record("pan-right-click-cancelled", "drawing is no longer the active eligible page"); return;
        }
        uint inserted, cleanup;
        bool ok = ReplayRightClick(delegate(NativeInput[] inputs) {
            return SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(NativeInput)));
        }, out inserted, out cleanup);
        Record(ok ? "pan-right-click" : "pan-right-click-failed",
            "native-input target=" + view.ToInt64().ToString("X") + " cursorPhysical=" + cursor.X + "," + cursor.Y
            + " inserted=" + inserted + " cleanup=" + cleanup + (ok ? "" : " win32=" + Marshal.GetLastWin32Error()));
    }

    // Direct pan never injects buttons or enters Capture's native pan mode.
    // A stationary single click is replayed separately, outside the hook.
    static bool PanTargetValid(POINT physical)
    {
        return PointerTargetValid(panView, panForeground, physical, true);
    }

    static bool PointerTargetValid(IntPtr view, IntPtr foreground, POINT physical, bool allowRightButton)
    {
        if (stateMode == 0 || !IsWindow(view) || !IsWindowEnabled(view)) return false;
        IntPtr top = GetForegroundWindow();
        if (top != foreground || !DrawingNavigationAllowed(top, view)) return false;
        uint pid; uint thread = GetWindowThreadProcessId(view, out pid);
        var gui = new GuiInfo(); gui.Size = Marshal.SizeOf(gui);
        if (!GetGUIThreadInfo(thread, ref gui) || (gui.Flags & ~1u) != 0 ||
            gui.Capture != IntPtr.Zero) return false;
        if (WindowFromPhysicalPoint(physical) != view) return false;
        foreach (int key in modifierKeys)
            if ((!allowRightButton || key != 2) && GetAsyncKeyState(key) < 0) return false;
        if (GetAsyncKeyState(0x1B) < 0) return false; // Escape cancels, never injected.
        return true;
    }

    static bool ReadScroll(IntPtr window, int bar, out SCROLLINFO info)
    {
        info = new SCROLLINFO(); info.Size = (uint)Marshal.SizeOf(info); info.Mask = 7;
        return GetScrollInfo(window, bar, ref info);
    }

    static bool NativeScrollbarUsable(IntPtr window, int bar)
    {
        if (!IsWindow(window)) return false;
        bool enabled = IsWindowEnabled(window), visible = IsWindowVisible(window);
        bool usable = ScrollbarUsable(enabled, visible);
        if (!usable) Record("pan-axis-unavailable", "bar=" + bar + " window=" + WindowInfo(window)
            + " enabled=" + enabled + " visible=" + visible);
        return usable;
    }

    static ScrollAxis MakeAxis(IntPtr owner, IntPtr control, int bar, int length, int startClient)
    {
        IntPtr scrollWindow = control == IntPtr.Zero ? owner : control;
        int scrollBar = control == IntPtr.Zero ? bar : 2; // SB_CTL for a scrollbar control.
        if (!NativeScrollbarUsable(scrollWindow, scrollBar)) return null;
        SCROLLINFO info;
        if (!ReadScroll(scrollWindow, scrollBar, out info)) return null;
        long limit = (long)info.Max - (info.Page > 0 ? (long)info.Page - 1 : 0);
        if (limit <= info.Min) return null; // Whole sheet visible: no scrollable extent.
        if (info.Pos < 0 || info.Pos > UInt16.MaxValue || info.Min < 0) {
            Record("pan-unsupported-scroll-range", "owner=" + WindowInfo(owner) + " axis=" + bar + " pos=" + info.Pos);
            return null;
        }
        var axis = new ScrollAxis();
        axis.Owner = owner; axis.Control = control; axis.ScrollWindow = scrollWindow; axis.Bar = scrollBar;
        axis.Message = bar == 0 ? WM_HSCROLL : WM_VSCROLL;
        axis.Initial = info; axis.StartPosition = info.Pos; axis.LastRequested = info.Pos;
        axis.StartClient = startClient; axis.ClientLength = length;
        Record("pan-axis-" + bar, "axis=" + bar + " owner=" + WindowInfo(owner) + " control=" + control.ToInt64().ToString("X")
            + " range=" + info.Min + ".." + info.Max + " page=" + info.Page + " pos=" + info.Pos + " client=" + length);
        return axis;
    }

    static bool BeginGrab()
    {
        RECT rect;
        IntPtr oldDpi = IntPtr.Zero;
        try {
            try { oldDpi = SetThreadDpiAwarenessContext(GetWindowDpiAwarenessContext(panView)); }
            catch (EntryPointNotFoundException) {}
            if (!GetClientRect(panView, out rect) || rect.R <= rect.L || rect.B <= rect.T) return false;
        } finally { if (oldDpi != IntPtr.Zero) SetThreadDpiAwarenessContext(oldDpi); }
        panHorizontal = null; panVertical = null;
        IntPtr childFrame = panView;
        var owners = new List<IntPtr>();
        // Prefer the drawing's own bars, then bars on its enclosing MDI child.
        // Stop at MDIClient: never borrow scrollbars from the project/command panes.
        for (IntPtr owner = panView; owner != IntPtr.Zero && ClassOf(owner) != "MDIClient"; owner = GetParent(owner)) {
            owners.Add(owner);
            if (panHorizontal == null) panHorizontal = MakeAxis(owner, IntPtr.Zero, 0, rect.R-rect.L, panStartClient.X);
            if (panVertical == null) panVertical = MakeAxis(owner, IntPtr.Zero, 1, rect.B-rect.T, panStartClient.Y);
            childFrame = owner;
            IntPtr parent = GetParent(owner);
            if (parent == IntPtr.Zero || ClassOf(parent) == "MDIClient") break;
        }
        if (panHorizontal == null || panVertical == null) {
            EnumChildWindows(childFrame, delegate(IntPtr control, IntPtr unused) {
                if (ClassOf(control) != "ScrollBar" || !owners.Contains(GetParent(control))) return true;
                bool vertical = (GetWindowLong(control, -16) & 1) != 0; // SBS_VERT.
                if (vertical && panVertical == null)
                    panVertical = MakeAxis(GetParent(control), control, 1, rect.B-rect.T, panStartClient.Y);
                if (!vertical && panHorizontal == null)
                    panHorizontal = MakeAxis(GetParent(control), control, 0, rect.R-rect.L, panStartClient.X);
                return true;
            }, IntPtr.Zero);
        }
        return panHorizontal != null || panVertical != null;
    }

    static AxisResult MoveAxis(ScrollAxis axis, int client)
    {
        if (axis == null || axis.Blocked) return AxisResult.Unavailable;
        if (!NativeScrollbarUsable(axis.ScrollWindow, axis.Bar)) { axis.Blocked = true; return AxisResult.Unavailable; }
        int position = GrabPosition(axis.StartPosition, axis.Initial.Min, axis.Initial.Max,
            axis.Initial.Page, axis.ClientLength, (long)client - axis.StartClient);
        if (position == axis.LastRequested) return AxisResult.Idle;
        if (position < 0 || position > UInt16.MaxValue) {
            Record("pan-unsupported-scroll-range", "desired=" + position); axis.Blocked = true; return AxisResult.Unavailable;
        }
        ScrollResult lastResponse = ScrollResult.Failed;
        ScrollTransport send = delegate(ScrollRoute route, int desired) {
            SCROLLINFO before;
            if (!ReadScroll(axis.ScrollWindow, axis.Bar, out before)) return lastResponse = ScrollResult.Failed;
            UIntPtr result;
            // SB_THUMBTRACK (5) is the live-position notification; (4) is just
            // release notification and was ignored in the actual 16.6 log.
            // A notification is not a simulated middle button or an OS drag loop.
            if (SendMessageTimeout(route.Target, (uint)axis.Message, new IntPtr(ScrollParameter(desired, LiveScrollCommand)),
                route.Control, 0x23, 30, out result) == IntPtr.Zero) {
                Record("pan-scroll-timeout", "axis=" + axis.Message.ToString("X") + " target=" + WindowInfo(route.Target));
                return lastResponse = ScrollResult.Failed;
            }
            SCROLLINFO after;
            if (!ReadScroll(axis.ScrollWindow, axis.Bar, out after)) return lastResponse = ScrollResult.Failed;
            ScrollResult response = after.Pos == desired ? ScrollResult.Applied :
                after.Pos == before.Pos ? ScrollResult.Unchanged : ScrollResult.UnexpectedPosition;
            Record(response == ScrollResult.Applied ? "pan-scrolled" : "pan-scroll-not-applied",
                "axis=" + axis.Message.ToString("X") + " command=5 target=" + WindowInfo(route.Target)
                + " control=" + route.Control.ToInt64().ToString("X")
                + " from=" + before.Pos + " desired=" + desired + " actual=" + after.Pos + " result=" + response);
            return lastResponse = response;
        };
        bool applied;
        if (axis.Route != null) applied = send(axis.Route, position) == ScrollResult.Applied;
        else applied = FindScrollRoute(ScrollRoutes(panView, axis.Owner, axis.Control), position, send, out axis.Route);
        axis.LastRequested = position;
        if (applied) return AxisResult.Applied;
        if (lastResponse == ScrollResult.Unchanged) {
            // A verified no-op is an axis limitation, not an uncertain command.
            // Keep the other axis live; retry availability on the next gesture.
            axis.Blocked = true;
            Record("pan-axis-blocked", "axis=" + axis.Message.ToString("X") + " other axis remains active");
            return AxisResult.Unavailable;
        }
        return AxisResult.Unsafe;
    }

    static void EndGrab(string reason)
    {
        panMovePending = false; panNeedsInit = false;
        ScrollAxis horizontal = panHorizontal, vertical = panVertical;
        panHorizontal = null; panVertical = null;
        foreach (ScrollAxis axis in new ScrollAxis[] {horizontal, vertical}) {
            if (axis == null || axis.Route == null || !IsWindow(axis.Route.Target) ||
                (axis.Route.Control != IntPtr.Zero && !IsWindow(axis.Route.Control))) continue;
            // End live scroll notifications on the SAME handler that responded.
            // No final position command that could move the view after release.
            UIntPtr result;
            if (SendMessageTimeout(axis.Route.Target, (uint)axis.Message, new IntPtr(8),
                axis.Route.Control, 0x23, 30, out result) == IntPtr.Zero)
                Record("pan-end-scroll-timeout", "axis=" + axis.Message.ToString("X"));
        }
        Record("pan-end", reason);
        // No synthetic button, middle-pan mode, OS mouse tracking or queued move.
    }

    static void CancelPan(string reason)
    {
        EndGrab(reason);
        pan.Cancel(); // Keep withholding this gesture's original right-up.
    }

    static void FlushPanMove()
    {
        if (pan.Mode != 2 || !panMovePending) return;
        if (!PanTargetValid(panLatest)) { CancelPan("left-canvas-or-scope"); return; }
        if (panNeedsInit) {
            panNeedsInit = false;
            if (!BeginGrab()) { Record("pan-no-scrollbars", "ancestors=" + Ancestors(panView)); CancelPan("no-scrollable-viewport"); return; }
            panCount++; Record("pan-start", "target=" + panView.ToInt64().ToString("X"));
        }
        POINT client;
        if (!ClientPoint(panView, panLatest, false, out client)) { CancelPan("client-conversion-failed"); return; }
        if (!MoveBothAxes(delegate { return MoveAxis(panHorizontal, client.X); },
            delegate { return MoveAxis(panVertical, client.Y); })) CancelPan("unsafe-scroll-result");
        panMovePending = false;
    }

    static bool HandlePan(int message, MouseData mouse)
    {
        if (message == WM_RBUTTONDOWN) {
            // A new physical down also resynchronizes after a missed up. Do not
            // consult the OS right-button state: the original down was withheld.
            if (pan.Mode != 0) { EndGrab("new-right-down"); pan.Release(); }
            IntPtr view; POINT screen, client;
            if (!Eligible(mouse.Point, out view, out screen, true) || !ClientPoint(view, mouse.Point, false, out client)) return false;
            panView = view; panForeground = GetForegroundWindow(); panStartClient = client; panLatest = mouse.Point;
            pan.Begin(mouse.Point.X, mouse.Point.Y);
            Record("pan-pending", "target=" + view.ToInt64().ToString("X"));
            return true;
        }
        if (pan.Mode == 0) return false;
        if (message == WM_MOUSEMOVE) {
            panLatest = mouse.Point;
            // Never block physical movement: the OS must move the cursor. Only
            // right button down/up are withheld, so no native right-drag begins.
            if (pan.Mode == 3) return false;
            if (!PanTargetValid(mouse.Point)) { CancelPan("left-canvas-or-scope"); return false; }
            // Physical pixels: minor hand shake must not consume a right click.
            if (pan.Move(mouse.Point.X, mouse.Point.Y, 6)) {
                // Defer scroll discovery to the frame timer. Do not put new
                // cross-process control queries on the mouse callback path.
                panNeedsInit = true;
                Record("pan-start-request", "target=" + panView.ToInt64().ToString("X"));
            }
            if (pan.Mode == 2) panMovePending = true;
            return false;
        }
        if (message == WM_RBUTTONUP) {
            panLatest = mouse.Point;
            if (pan.Mode == 1 && PanTargetValid(mouse.Point)) {
                POINT client;
                if (ClientPoint(panView, mouse.Point, false, out client)) {
                    clickReplayView = panView; clickReplayForeground = panForeground;
                    clickReplayPoint = mouse.Point; clickReplayQueuedAt = DateTime.UtcNow;
                    Record("pan-right-click-queued", "target=" + panView.ToInt64().ToString("X")
                        + " cursorPhysical=" + mouse.Point.X + "," + mouse.Point.Y + " client=" + client.X + "," + client.Y);
                }
            } else {
                if (pan.Mode == 2) panMovePending = true;
                FlushPanMove();
                EndGrab("right-released");
            }
            pan.Release(); panView = IntPtr.Zero;
            return true;
        }
        if (message == WM_MOUSEWHEEL) return WheelBlockedByPan(pan.Mode);
        // Additional buttons cancel pan, but retain their original operation.
        if (message == 0x0201 || message == 0x0207 || message == 0x020B)
            CancelPan("other-button");
        return false;
    }

    static IntPtr OnMouse(int code, IntPtr message, IntPtr data)
    {
        if (code >= 0)
        {
            mouseCallbacks++;
            try
            {
                if (!MouseMessageRelevant(message.ToInt32(), pan.Mode)) return CallNextHookEx(hook, code, message, data);
                var m = (MouseData)Marshal.PtrToStructure(data, typeof(MouseData));
                int kind = message.ToInt32();
                if (IsOwnRightClick(kind, m.Extra)) return CallNextHookEx(hook, code, message, data);
                if (kind == WM_MOUSEWHEEL || kind == WM_RBUTTONDOWN || kind == 0x0201 || kind == 0x0207 || kind == 0x020B)
                    clickReplayView = IntPtr.Zero; // A new user action cancels an older deferred click.
                if (kind == WM_MOUSEWHEEL) rawWheels++;
                if (kind == WM_RBUTTONDOWN) { rawRightDowns++; Record("right-down-received", "flags=" + m.Flags); }
                if ((m.Flags & 1u) != 0) {
                    if (kind == WM_MOUSEWHEEL || kind == WM_RBUTTONDOWN || kind == WM_RBUTTONUP)
                        Record("injected-mouse-input-accepted", "message=" + kind.ToString("X") + " flags=" + m.Flags + "; same drawing scope checks apply");
                }
                if (HandlePan(kind, m)) return new IntPtr(1);
                if (kind != WM_MOUSEWHEEL) return CallNextHookEx(hook, code, message, data);
                receivedWheels++;
                IntPtr view;
                POINT messagePoint;
                if (Eligible(m.Point, out view, out messagePoint))
                {
                    // PostMessage does not return through the low-level hook (no recursion).
                    // MK_CONTROL requests native zoom without pressing/releasing any keys.
                    int w = WheelParameter(m.Data);
                    int l = PointParameter(messagePoint.X, messagePoint.Y);
                    if (PostMessage(view, WM_MOUSEWHEEL, new IntPtr(w), new IntPtr(l)))
                    { wheelCount++; Record("posted", "target=" + view.ToInt64().ToString("X")); return new IntPtr(1); }
                    Record("post-failed", "win32=" + Marshal.GetLastWin32Error());
                }
            }
            catch (Exception ex) {
                Record("exception", ex.GetType().Name + ": " + ex.Message);
                if (pan.Mode != 0) {
                    try { CancelPan("exception"); } catch { pan.Cancel(); }
                    if (message.ToInt32() == WM_RBUTTONUP) pan.Release();
                    if (message.ToInt32() == WM_RBUTTONDOWN || message.ToInt32() == WM_RBUTTONUP) return new IntPtr(1);
                }
            }
        }
        return CallNextHookEx(hook, code, message, data);
    }

    static void CheckInputHook()
    {
        POINT cursor;
        if (!GetPhysicalCursorPos(out cursor)) return;
        IntPtr foreground = GetForegroundWindow();
        uint pid; GetWindowThreadProcessId(foreground, out pid);
        bool inScope = stateMode != 0 && pid == capturePid;
        if (!inScope && stateMode == 2) {
            IntPtr hit = WindowFromPhysicalPoint(cursor);
            inScope = ClassOf(hit) == "OrRandomView" && GetDlgCtrlID(hit) == 0xE900
                && DrawingNavigationAllowed(foreground, hit);
        }
        if (!inputWatchdog.Sample(cursor.X, cursor.Y, mouseCallbacks, inScope)) return;
        // Windows may remove a timed-out low-level hook without notifying its
        // owner. Rearm only when physical cursor motion repeatedly lacks any
        // hook callback, not merely because the user is idle or using a keyboard.
        EndGrab("input-hook-recovery"); pan.Release();
        if (hook != IntPtr.Zero) UnhookWindowsHookEx(hook);
        hook = SetWindowsHookEx(WH_MOUSE_LL, callback, GetModuleHandle(null), 0);
        if (hook == IntPtr.Zero) throw new System.ComponentModel.Win32Exception();
        hookRearms++; Log("Input hook rearmed after cursor motion without callbacks; rearm=" + hookRearms);
    }

    // Separate one-shot process, no wheel preference changes. Capture's
    // custom MFC popup need not be #32768 / HMENU or set GUI_INMENUMODE.
    // Execute the enabled Signals MENUITEM in the newly opened Capture-owned
    // popup through MSAA. Never guess coordinates, send mnemonics, or blindly
    // dispatch the cached command 14844 after merely opening the popup.
    internal static bool SignalsMenuItemAllowed(uint id, uint state, IntPtr subMenu)
    { return id == 14844 && (state & 3u) == 0 && subMenu == IntPtr.Zero; }

    internal static bool SignalsAccessibleItemAllowed(string name, int role, int state)
    {
        if (name == null || role != 12) return false; // ROLE_SYSTEM_MENUITEM
        // UNAVAILABLE, INVISIBLE, OFFSCREEN, HASPOPUP.
        if ((state & (1 | 0x8000 | 0x10000 | 0x40000000)) != 0) return false;
        string label = name.Split('\t')[0].Replace("&", "").Trim();
        return label.Equals("Signals", StringComparison.OrdinalIgnoreCase);
    }

    internal static void WriteSignalsResult(string resultPath, string result)
    {
        // Publish only a complete UTF-8 acknowledgement, never a partial write.
        string staging = resultPath + ".writing";
        bool created = false;
        try {
            using (var stream = new FileStream(staging, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {created = true; using (var writer = new StreamWriter(stream, new UTF8Encoding(false))) {writer.Write(result);}}
            File.Move(staging, resultPath);
        } finally {if (created && File.Exists(staging)) File.Delete(staging);}
    }

    sealed class SignalsAccessibleItem
    {
        internal IAccessible Parent;
        internal object Child;
        internal IntPtr Window;
    }

    internal enum SignalsCleanupProbe { Gone, Safe, Unsafe }
    internal enum SignalsCleanupResult { Closed, Skipped, StillOpen }
    // https://learn.microsoft.com/en-us/windows/win32/winmsg/wm-cancelmode
    internal const uint SignalsCancelMessage = 0x001F; // WM_CANCELMODE
    internal const uint SignalsEscapeMessage = 0x0100; // WM_KEYDOWN, only to captured popup

    internal static bool SignalsGestureMessage(bool keyboard, int message, UIntPtr extra)
    {
        if (keyboard) return message == 0x0100 || message == 0x0101 || message == 0x0104 || message == 0x0105;
        // Hover is not a new gesture. Ignore only our tagged native right-click
        // pair; injected clicks from drivers/accessibility still count.
        if (IsOwnRightClick(message, extra)) return false;
        return message >= 0x0201 && message <= 0x020E;
    }

    internal sealed class SignalsGestureState
    {
        int generation;
        readonly bool[] initialKeys = new bool[256];
        internal int Generation { get { return Interlocked.CompareExchange(ref generation, 0, 0); } }
        // Called on the observer thread after installing hooks, before pumping
        // their callbacks. Transient held-state only; no key content or history.
        internal void SeedHeldKeys(Func<int, bool> down)
        { for (int key=8; key<initialKeys.Length; key++) initialKeys[key] = key != 0x1B && down(key); }
        internal void ObserveKeyboard(int message, int key)
        {
            if (!SignalsGestureMessage(true, message, UIntPtr.Zero)) return;
            bool up = message == 0x0101 || message == 0x0105;
            if (key >= 8 && key < initialKeys.Length && initialKeys[key]) {
                // Original shortcut autorepeat/release is not a new action.
                // Once released, pressing it again DOES cancel the request.
                if (up) initialKeys[key] = false;
                return;
            }
            Interlocked.Increment(ref generation);
        }
        internal void Observe(bool keyboard, int message, UIntPtr extra)
        { if (SignalsGestureMessage(keyboard, message, extra)) Interlocked.Increment(ref generation); }
        internal bool Unchanged(int checkpoint) { return Generation == checkpoint; }
    }

    // Short-lived, read-only observer for this single Alt+S request. A dedicated
    // message-pump thread keeps callbacks responsive while cross-process MSAA
    // runs. Never swallow/replay input, record key values, or log mouse motion.
    // https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelmouseproc
    internal sealed class SignalsGestureObserver : IDisposable
    {
        internal readonly SignalsGestureState State = new SignalsGestureState();
        readonly ManualResetEvent ready = new ManualResetEvent(false);
        readonly Thread worker;
        readonly HookProc mouseCallback, keyboardCallback;
        IntPtr mouseHook, keyboardHook;
        uint threadId;
        volatile bool stopped, listening;
        internal bool Ready { get { return listening && !stopped; } }
        internal bool HasExited { get { return !worker.IsAlive; } }

        internal SignalsGestureObserver()
        {
            mouseCallback = delegate(int code, IntPtr message, IntPtr data) {
                if (code >= 0 && message.ToInt32() != WM_MOUSEMOVE) {
                    MouseData input = (MouseData)Marshal.PtrToStructure(data, typeof(MouseData));
                    State.Observe(false, message.ToInt32(), input.Extra);
                }
                return CallNextHookEx(mouseHook, code, message, data);
            };
            keyboardCallback = delegate(int code, IntPtr message, IntPtr data) {
                // KBDLLHOOKSTRUCT begins with DWORD vkCode. Do not retain/log it.
                if (code >= 0) State.ObserveKeyboard(message.ToInt32(), Marshal.ReadInt32(data));
                return CallNextHookEx(keyboardHook, code, message, data);
            };
            worker = new Thread(Run);
            worker.IsBackground = true;
            worker.Name = "Signals gesture guard";
            worker.Start();
            // Done BEFORE opening the popup, so setup does not extend its flash.
            if (!ready.WaitOne(200)) stopped = true;
        }

        void Run()
        {
            try {
                threadId = GetCurrentThreadId();
                using (var context = new ApplicationContext())
                using (var lifetime = new System.Windows.Forms.Timer()) {
                    mouseHook = SetWindowsHookEx(WH_MOUSE_LL, mouseCallback, GetModuleHandle(null), 0);
                    keyboardHook = SetWindowsHookEx(13, keyboardCallback, GetModuleHandle(null), 0);
                    if (mouseHook == IntPtr.Zero || keyboardHook == IntPtr.Zero) return;
                    State.SeedHeldKeys(delegate(int key) { return GetAsyncKeyState(key) < 0; });
                    // Timer creates the message queue before publishing readiness.
                    // Self-expire even if an accessibility call hangs in Capture.
                    lifetime.Interval = 10000;
                    lifetime.Tick += delegate { context.ExitThread(); };
                    lifetime.Start();
                    listening = true;
                    ready.Set();
                    if (!stopped) Application.Run(context);
                }
            } catch { /* Missing observer means cleanup is skipped, not retried. */ }
            finally {
                listening = false;
                if (mouseHook != IntPtr.Zero) UnhookWindowsHookEx(mouseHook);
                if (keyboardHook != IntPtr.Zero) UnhookWindowsHookEx(keyboardHook);
                ready.Set();
            }
        }

        public void Dispose()
        {
            stopped = true;
            if (threadId != 0) PostThreadMessage(threadId, 0x0012, IntPtr.Zero, IntPtr.Zero); // WM_QUIT
            if (worker.Join(200)) ready.Close();
        }
    }

    internal static bool SignalsPopupStyleAllowed(uint style)
    {
        // Standard/MFC menus may have WS_BORDER, but are not captioned/system
        // menu windows or child controls. Reject floating panes and dialogs.
        return (style & 0x80000000u) != 0 && (style & 0x40000000u) == 0
            && (style & 0x00080000u) == 0 && (style & 0x00C00000u) != 0x00C00000u;
    }

    internal static bool SignalsCleanupTargetAllowed(bool newlyCreated, bool inCaptureScope,
        bool popupStyle, bool applicationWindow, string className)
    {
        // A previously identified Signals MENUITEM is also required by the caller.
        // Never dismiss the drawing, main frame, a dialog or a floating result pane.
        return newlyCreated && inCaptureScope && popupStyle && !applicationWindow
            && (className == "#32768" || (className != null && className.StartsWith("Afx", StringComparison.Ordinal)));
    }

    internal static SignalsCleanupProbe SignalsCleanupEligibility(bool visible, bool sameIdentity,
        bool allowedTarget, bool sameContext, bool sameInput)
    {
        if (!visible) return SignalsCleanupProbe.Gone;
        return sameIdentity && allowedTarget && sameContext && sameInput
            ? SignalsCleanupProbe.Safe : SignalsCleanupProbe.Unsafe;
    }

    internal static SignalsCleanupResult FinishSignalsPopup(Func<SignalsCleanupProbe> probe,
        Action<uint> dismiss, Action<int> pause)
    {
        SignalsCleanupProbe state = probe();
        if (state == SignalsCleanupProbe.Gone) return SignalsCleanupResult.Closed;
        if (state == SignalsCleanupProbe.Unsafe) return SignalsCleanupResult.Skipped;
        // No grace delay: already-closed menus get no messages; an exact still-
        // visible popup is cancelled as soon as Signals returns.
        foreach (uint message in new uint[] {SignalsCancelMessage, SignalsEscapeMessage}) {
            state = probe();
            if (state == SignalsCleanupProbe.Gone) return SignalsCleanupResult.Closed;
            if (state == SignalsCleanupProbe.Unsafe) return SignalsCleanupResult.Skipped;
            dismiss(message);
            for (int attempt=0; attempt<3; attempt++) {
                pause(10);
                state = probe();
                if (state == SignalsCleanupProbe.Gone) return SignalsCleanupResult.Closed;
                if (state == SignalsCleanupProbe.Unsafe) return SignalsCleanupResult.Skipped;
            }
        }
        return SignalsCleanupResult.StillOpen;
    }

    sealed class SignalsPopupTicket
    {
        internal IntPtr Window, MatchedWindow, OwnerRoot;
        internal string ClassName;
        internal uint Thread;
        internal int GestureCheckpoint;
        internal bool Allowed;
        internal SignalsGestureObserver Input;
    }

    static SignalsPopupTicket CaptureSignalsPopup(SignalsAccessibleItem item,
        HashSet<IntPtr> baseline, IntPtr foreground, IntPtr view, SignalsGestureObserver input)
    {
        // Resolve an accessible child to its popup root BEFORE invoking Signals.
        var ticket = new SignalsPopupTicket();
        ticket.MatchedWindow = item.Window;
        ticket.Window = GetAncestor(item.Window, 2); // GA_ROOT, not ROOTOWNER
        ticket.ClassName = ClassOf(ticket.Window);
        ticket.OwnerRoot = GetAncestor(ticket.Window, 3);
        uint pid;
        ticket.Thread = GetWindowThreadProcessId(ticket.Window, out pid);
        ticket.Allowed = SignalsCleanupTargetAllowed(!baseline.Contains(ticket.Window),
            pid == capturePid && SignalsPopupInScope(ticket.Window, foreground, view),
            SignalsPopupStyleAllowed(unchecked((uint)GetWindowLong(ticket.Window, -16))),
            ticket.Window == foreground || ticket.Window == view || ticket.Window == GetAncestor(foreground, 2)
                || ticket.Window == GetAncestor(view, 2), ticket.ClassName);
        ticket.Input = input;
        ticket.GestureCheckpoint = input.State.Generation;
        Log("Signals cleanup ticket: window=" + ticket.Window.ToInt64().ToString("X")
            + " class=" + ticket.ClassName + " allowed=" + ticket.Allowed + " observerReady=" + input.Ready);
        return ticket;
    }

    static SignalsCleanupProbe ProbeSignalsPopup(SignalsPopupTicket ticket, IntPtr foreground, IntPtr view)
    {
        if (ticket.Window == IntPtr.Zero) {
            return !IsWindow(ticket.MatchedWindow) || !IsWindowVisible(ticket.MatchedWindow)
                ? SignalsCleanupProbe.Gone : SignalsCleanupProbe.Unsafe;
        }
        bool visible = IsWindow(ticket.Window) && IsWindowVisible(ticket.Window);
        if (!visible) return SignalsCleanupProbe.Gone;
        uint pid;
        bool identity = GetWindowThreadProcessId(ticket.Window, out pid) == ticket.Thread
            && pid == capturePid && ClassOf(ticket.Window) == ticket.ClassName
            && GetAncestor(ticket.Window, 3) == ticket.OwnerRoot
            && SignalsPopupStyleAllowed(unchecked((uint)GetWindowLong(ticket.Window, -16)));
        bool unchangedInput = ticket.Input.Ready && ticket.Input.State.Unchanged(ticket.GestureCheckpoint);
        foreach (int key in modifierKeys)
            if (ScopeInputBlocks(key, false, true) && GetAsyncKeyState(key) < 0) unchangedInput = false;
        if (GetAsyncKeyState(0x1B) < 0) unchangedInput = false;
        bool context = GetForegroundWindow() == foreground && IsWindow(view) && IsWindowEnabled(view)
            && SignalsPopupInScope(ticket.Window, foreground, view) && DrawingBelongsToForeground(foreground, view);
        SignalsCleanupProbe result = SignalsCleanupEligibility(visible, identity, ticket.Allowed, context, unchangedInput);
        if (result == SignalsCleanupProbe.Unsafe) Log("Signals cleanup guard: identity=" + identity
            + " allowed=" + ticket.Allowed + " context=" + context + " gestureUnchanged=" + unchangedInput
            + " foreground=" + GetForegroundWindow().ToInt64().ToString("X")
            + " expectedForeground=" + foreground.ToInt64().ToString("X"));
        return result;
    }

    static SignalsCleanupResult CompleteSignalsPopup(SignalsPopupTicket ticket, IntPtr foreground, IntPtr view)
    {
        try {
            SignalsCleanupResult result = FinishSignalsPopup(
                delegate { return ProbeSignalsPopup(ticket, foreground, view); },
                delegate(uint message) {
                    // Revalidate immediately before posting; never send Escape
                    // to Capture's frame/drawing or use global keyboard input.
                    if (ProbeSignalsPopup(ticket, foreground, view) != SignalsCleanupProbe.Safe) return;
                    IntPtr key = message == SignalsEscapeMessage ? new IntPtr(0x1B) : IntPtr.Zero;
                    IntPtr data = message == SignalsEscapeMessage ? new IntPtr(0x00010001) : IntPtr.Zero;
                    bool posted = PostMessage(ticket.Window, message, key, data);
                    Log("Signals popup cleanup message=" + message.ToString("X") + " posted=" + posted
                        + " window=" + ticket.Window.ToInt64().ToString("X"));
                }, Thread.Sleep);
            Log("Signals popup cleanup=" + result + "; Signals will not be invoked again");
            return result;
        } catch (Exception ex) {
            // The Signals action has already returned; never turn a cleanup
            // exception into a failed-action acknowledgement or retry the action.
            Log("Signals popup cleanup skipped after action: " + ex.Message);
            return SignalsCleanupResult.Skipped;
        }
    }

    internal static bool SignalsPopupScopeAllowed(bool captureProcess, bool visible, bool sameOwner, bool sameDrawingThread)
    { return captureProcess && visible && (sameOwner || sameDrawingThread); }

    static bool SignalsPopupInScope(IntPtr window, IntPtr foreground, IntPtr view)
    {
        uint pid, viewPid;
        uint thread = GetWindowThreadProcessId(window, out pid);
        uint viewThread = GetWindowThreadProcessId(view, out viewPid);
        return SignalsPopupScopeAllowed(pid == capturePid && viewPid == capturePid, IsWindowVisible(window),
            GetAncestor(window, 3) == GetAncestor(foreground, 3), thread != 0 && thread == viewThread);
    }

    static List<IntPtr> CaptureVisibleWindows(IntPtr foreground, IntPtr view)
    {
        var windows = new List<IntPtr>();
        EnumWindows(delegate(IntPtr window, IntPtr unused) {
            if (!SignalsPopupInScope(window, foreground, view)) return true;
            windows.Add(window);
            EnumChildWindows(window, delegate(IntPtr child, IntPtr arg) {
                uint childPid; GetWindowThreadProcessId(child, out childPid);
                if (childPid == capturePid && IsWindowVisible(child)) windows.Add(child);
                return true;
            }, IntPtr.Zero);
            return true;
        }, IntPtr.Zero);
        return windows;
    }

    static void ScanSignalsAccessible(IAccessible accessible, object child, IntPtr window,
        List<SignalsAccessibleItem> matches, int depth, ref int budget, Stopwatch request)
    {
        if (accessible == null || depth > 6 || --budget < 0 || request.ElapsedMilliseconds > 3000) return;
        try {
            int role = Convert.ToInt32(accessible.get_accRole(child));
            int state = Convert.ToInt32(accessible.get_accState(child));
            // Capture's unnamed popup root throws E_INVALIDARG for accName(0).
            // Only leaf MENUITEM names are relevant; still traverse the root.
            string name = role == 12 ? accessible.get_accName(child) : null;
            if (SignalsAccessibleItemAllowed(name, role, state)) {
                matches.Add(new SignalsAccessibleItem {Parent=accessible, Child=child, Window=window});
                return;
            }
            // Simple children have no descendants. Ignore hidden branches.
            if (!(child is int) || (int)child != 0 || (state & (0x8000 | 0x10000)) != 0) return;
            int count = Math.Min(accessible.accChildCount, 128);
            if (count <= 0) return;
            var children = new object[count]; int obtained;
            if (AccessibleChildren(accessible, 0, count, children, out obtained) < 0) return;
            for (int i=0; i < obtained && budget > 0 && request.ElapsedMilliseconds <= 3000; i++) {
                var nested = children[i] as IAccessible;
                if (nested != null) ScanSignalsAccessible(nested, 0, window, matches, depth+1, ref budget, request);
                else if (children[i] is int) ScanSignalsAccessible(accessible, children[i], window, matches, depth+1, ref budget, request);
            }
        } catch (ArgumentException) { }
        catch (COMException) {} catch (InvalidCastException) {} catch (FormatException) {}
    }

    static SignalsAccessibleItem FindSignalsAccessible(List<IntPtr> candidates, Stopwatch request)
    {
        var guid = new Guid("618736E0-3C3D-11CF-810C-00AA00389B71");
        foreach (IntPtr window in candidates) {
            if (request.ElapsedMilliseconds > 3000) break;
            // CLIENT for custom MFC, MENU for standard popup, then WINDOW root.
            foreach (uint objectId in new uint[] {unchecked((uint)-4), unchecked((uint)-3), 0}) {
                IAccessible accessible;
                try {
                    if (AccessibleObjectFromWindow(window, objectId, ref guid, out accessible) < 0 || accessible == null) continue;
                } catch (ArgumentException ex) {Log("MSAA object rejected window=" + window + " object=" + objectId + ": " + ex); continue;}
                var matches = new List<SignalsAccessibleItem>(); int budget = 384;
                ScanSignalsAccessible(accessible, 0, window, matches, 0, ref budget, request);
                if (matches.Count > 1) throw new InvalidOperationException("Ambiguous Signals items; nothing invoked");
                if (matches.Count == 1) return matches[0];
            }
        }
        return null;
    }

    static int PrepareSignalsContext(string resultPath)
    {
        logPath = Path.Combine(Path.GetTempPath(), "OrCADSignalsNavigation-native.log");
        IntPtr foreground = IntPtr.Zero, view = IntPtr.Zero;
        var discovered = new HashSet<IntPtr>();
        bool invoked = false;
        SignalsGestureObserver input = null;
        try {
            Log("Signals request started: " + Version + "; Capture pid=" + capturePid);
            using (var target = Process.GetProcessById(capturePid)) {
                if (!target.ProcessName.Equals("Capture", StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Target is not Capture");
            }
            ConfigureDpi(); stateMode = 2;
            // No Alt/S-specific release wait. Tcl may remap the binding; the
            // observer below tolerates original held keys/release, not new input.
            var wait = Stopwatch.StartNew();
            if (GetAsyncKeyState(0x1B) < 0) throw new InvalidOperationException("Signals request cancelled by Escape");
            foreground = GetForegroundWindow();
            uint pid; GetWindowThreadProcessId(foreground, out pid);
            if (pid != capturePid) throw new InvalidOperationException("Capture lost foreground");
            POINT point, logical;
            if (!GetPhysicalCursorPos(out point) || !Eligible(point, out view, out logical, false, true))
                throw new InvalidOperationException("Keep pointer over the selected network wire in the current drawing");
            var baseline = new HashSet<IntPtr>(CaptureVisibleWindows(foreground, view));
            Log("Window discovery baseline=" + baseline.Count + " foreground=" + foreground + " view=" + view);
            foreach (int key in modifierKeys) if (ScopeInputBlocks(key, false, true) && GetAsyncKeyState(key) < 0)
                throw new InvalidOperationException("Release mouse buttons before running Signals");
            input = new SignalsGestureObserver();
            int openingCheckpoint = input.State.Generation;
            Log("Signals gesture observer ready=" + input.Ready);
            uint inserted, cleanup;
            if (!ReplayRightClick(delegate(NativeInput[] inputs) {
                return SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(NativeInput)));
            }, out inserted, out cleanup)) throw new InvalidOperationException("Native right click failed: " + inserted);
            wait.Restart(); SignalsAccessibleItem item = null;
            while (wait.ElapsedMilliseconds < 3000) {
                POINT current;
                if (GetForegroundWindow() != foreground || !GetPhysicalCursorPos(out current)
                    || Math.Abs((long)current.X-point.X) >= 6 || Math.Abs((long)current.Y-point.Y) >= 6)
                    throw new InvalidOperationException("Pointer or active window changed during Signals request");
                if (GetAsyncKeyState(0x1B) < 0) throw new InvalidOperationException("Signals request cancelled by Escape");
                var candidates = new List<IntPtr>();
                foreach (IntPtr window in CaptureVisibleWindows(foreground, view)) if (!baseline.Contains(window)) {
                    candidates.Add(window);
                    if (discovered.Add(window)) Log("New context window=" + window.ToInt64().ToString("X") + " class=" + ClassOf(window));
                }
                item = FindSignalsAccessible(candidates, wait);
                if (item != null) break;
                Thread.Sleep(30);
            }
            if (item == null) throw new InvalidOperationException("No accessible enabled Signals menu item; new windows=" + discovered.Count);
            POINT finalPoint;
            if (wait.ElapsedMilliseconds > 3000 || !SignalsPopupInScope(item.Window, foreground, view) || GetForegroundWindow() != foreground
                || !GetPhysicalCursorPos(out finalPoint) || Math.Abs((long)finalPoint.X-point.X) >= 6
                || Math.Abs((long)finalPoint.Y-point.Y) >= 6 || GetAsyncKeyState(0x1B) < 0)
                throw new InvalidOperationException("Signals menu changed or request expired; nothing invoked");
            foreach (int key in modifierKeys) if (ScopeInputBlocks(key, false, true) && GetAsyncKeyState(key) < 0)
                throw new InvalidOperationException("New mouse/key gesture cancelled Signals request");
            if (!SignalsAccessibleItemAllowed(item.Parent.get_accName(item.Child), Convert.ToInt32(item.Parent.get_accRole(item.Child)),
                Convert.ToInt32(item.Parent.get_accState(item.Child)))) throw new InvalidOperationException("Signals item became unavailable");
            // Cross-process accessibility reads may block. Check the deadline
            // again after the last read; an expired helper must never act later.
            if (wait.ElapsedMilliseconds > 3000 || GetForegroundWindow() != foreground || GetAsyncKeyState(0x1B) < 0)
                throw new InvalidOperationException("Signals request expired or cancelled during menu readback");
            if (input.Ready && !input.State.Unchanged(openingCheckpoint))
                throw new InvalidOperationException("New mouse/key gesture cancelled Signals request");
            // An uncertain action is never retried with 14844; it may have run.
            SignalsPopupTicket popupTicket = CaptureSignalsPopup(item, baseline, foreground, view, input);
            Log("Invoking accessible Signals menu action: window=" + item.Window.ToInt64().ToString("X") + " class=" + ClassOf(item.Window));
            invoked = true;
            item.Parent.accDoDefaultAction(item.Child);
            Log("Signals menu action returned; native pane result not verified");
            SignalsCleanupResult cleanupResult = CompleteSignalsPopup(popupTicket, foreground, view);
            WriteSignalsResult(resultPath, cleanupResult == SignalsCleanupResult.StillOpen
                ? "signals-invoked-menu-open" : "signals-invoked"); return 0;
        } catch (Exception ex) {
            Log("Signals menu action failed: " + ex);
            try {WriteSignalsResult(resultPath, "error: " + ex.Message);} catch {}
            return 1;
        } finally {
            // Dismiss only newly-created, Capture-owned visible windows, never
            // inject Escape into the user's drawing or another application's UI.
            if (!invoked && GetForegroundWindow() == foreground) foreach (IntPtr window in discovered) {
                if (SignalsPopupInScope(window, foreground, view))
                    PostMessage(window, 0x001F, IntPtr.Zero, IntPtr.Zero);
            }
            if (input != null) input.Dispose();
        }
    }

    internal static bool SignalsLaunchReady(string marker)
    { return marker == "capture-ready-v17"; }

    // Tcl 8.4's Windows process launcher waits for a GUI child's input-idle
    // state even with exec ... &. Start a message loop FIRST; do not inject
    // the right click until Capture confirms exec returned. No visible form,
    // hooks, focus changes or input before that handshake.
    static int RunSignalsContext(string resultPath)
    {
        ConfigureDpi();
        int result = 1;
        var elapsed = Stopwatch.StartNew();
        using (var context = new ApplicationContext())
        using (var timer = new System.Windows.Forms.Timer()) {
            timer.Interval = 30;
            timer.Tick += delegate {
                string marker = null;
                try { if (File.Exists(resultPath + ".ready")) marker = File.ReadAllText(resultPath + ".ready"); }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
                if (!SignalsLaunchReady(marker) && elapsed.ElapsedMilliseconds < 6500) return;
                timer.Stop();
                try {
                    if (!SignalsLaunchReady(marker)) {
                        logPath = Path.Combine(Path.GetTempPath(), "OrCADSignalsNavigation-native.log");
                        Log("Capture launch handshake timed out; no input sent");
                        WriteSignalsResult(resultPath, "error: Capture launch handshake timed out; update both TCL and EXE");
                    } else {
                        result = PrepareSignalsContext(resultPath);
                    }
                } finally { context.ExitThread(); }
            };
            timer.Start();
            Application.Run(context);
        }
        return result;
    }

    [STAThread] static int Main(string[] args)
    {
        if (args.Length < 2 || !Int32.TryParse(args[1], out capturePid)) return 2;
        if (args[0] == "--signals-context" && args.Length == 3) return RunSignalsContext(Path.GetFullPath(args[2]));
        string name = "Local\\OrCADQuickToolsWheel_" + capturePid;
        if (args[0] == "--stop")
        {
            try {
                using (var e = EventWaitHandle.OpenExisting(name)) { e.Set(); }
                using (var m = Mutex.OpenExisting(name + "_single")) {
                    bool owned = false;
                    try { owned = m.WaitOne(2000); } catch (AbandonedMutexException) { owned = true; }
                    if (owned) m.ReleaseMutex(); else return 1;
                }
            } catch (WaitHandleCannotBeOpenedException) {} catch { return 1; }
            return 0;
        }
        if (args[0] != "--run" || args.Length != 3) return 2;
        statePath = Path.GetFullPath(args[2]);
        logPath = Path.Combine(Path.GetTempPath(), "OrCADWheelZoom-" + capturePid + ".log");
        bool created;
        using (var mutex = new Mutex(true, name + "_single", out created))
        {
            if (!created) return 0;
            try
            {
                capture = Process.GetProcessById(capturePid);
                if (!capture.ProcessName.Equals("Capture", StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("Target process is not Capture.");
                string dpiMode = ConfigureDpi();
                stop = new EventWaitHandle(false, EventResetMode.ManualReset, name);
                System.Runtime.CompilerServices.RuntimeHelpers.PrepareDelegate(callback);
                hook = SetWindowsHookEx(WH_MOUSE_LL, callback, GetModuleHandle(null), 0);
                if (hook == IntPtr.Zero) throw new System.ComponentModel.Win32Exception();
                Log("Started " + Version + "; dpi=" + dpiMode + "; bitness=" + (IntPtr.Size * 8) + ". No keyboard injection.");
                Status("running");
                var timer = new System.Windows.Forms.Timer(); timer.Interval = 100;
                timer.Tick += delegate {
                    if (capture.HasExited || stop.WaitOne(0)) {
                        Log("Exit reason=" + (capture.HasExited ? "capture-exited" : "stop-requested"));
                        Application.ExitThread(); return;
                    }
                    if (++timerTicks % 5 == 0) {
                        try { CheckInputHook(); } catch (Exception ex) {
                            Log("ERROR input hook recovery: " + ex.Message); Status("error: " + ex.Message); Application.ExitThread(); return;
                        }
                        Status("running callbacks=" + mouseCallbacks + " rawWheels=" + rawWheels + " rightDowns=" + rawRightDowns
                            + " received=" + receivedWheels + " remapped=" + wheelCount + " pans=" + panCount + " rearmed=" + hookRearms);
                        foreach (var reason in reasonCounts)
                            Log("reason=" + reason.Key + " count=" + reason.Value + "; " + reasonDetails[reason.Key] + "; posted=" + wheelCount);
                        reasonCounts.Clear(); reasonDetails.Clear();
                    }
                    try {
                        bool fresh = (DateTime.UtcNow - File.GetLastWriteTimeUtc(statePath)).TotalSeconds < 2;
                        string state = ReadControllerState();
                        int previous = stateMode;
                        stateMode = RetainedStateMode(state, fresh, previous);
                        if (state.Length != 0 && fresh) lastControllerRead = DateTime.UtcNow;
                        if (previous != stateMode) Log("Controller mode " + previous + " -> " + stateMode + "; fresh=" + fresh);
                        active = fresh && (state == "1" || state == "hover 1");
                    } catch (Exception ex) {
                        // A short sharing/read failure is retried next tick. A
                        // stale/missing controller still disables routing safely.
                        if ((DateTime.UtcNow - lastControllerRead).TotalSeconds >= 2) {
                            if (stateMode != 0) Log("Controller unavailable; navigation paused: " + ex.Message);
                            active = false; stateMode = 0;
                        }
                    }
                };
                var panTimer = new System.Windows.Forms.Timer(); panTimer.Interval = 16;
                panTimer.Tick += delegate {
                    try {
                        FlushRightClick();
                        if (pan.Mode == 1 || pan.Mode == 2) {
                            if (!PanTargetValid(panLatest)) CancelPan("scope-changed");
                            else FlushPanMove();
                        }
                    } catch (Exception ex) { CancelPan("timer: " + ex.Message); }
                };
                timer.Start(); panTimer.Start(); Application.Run(); panTimer.Dispose(); timer.Dispose();
                Log("Stopped. callbacks=" + mouseCallbacks + "; rawWheels=" + rawWheels + "; rightDowns=" + rawRightDowns
                    + "; received=" + receivedWheels + "; remapped=" + wheelCount + "; pans=" + panCount + "; rearmed=" + hookRearms);
                Status("stopped");
                return 0;
            }
            catch (Exception ex) { Log("ERROR: " + ex.Message); Status("error: " + ex.Message); return 1; }
            finally { EndGrab("shutdown"); pan.Release(); if (hook != IntPtr.Zero) UnhookWindowsHookEx(hook); if (stop != null) stop.Dispose(); if (capture != null) capture.Dispose(); }
        }
    }
}
