// Default: pure policy/ABI tests, no hooks or Capture interaction.
// Optional --signals-guard-smoke: read-only hook startup/teardown, no UI input.
using System;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;

internal static class WheelNativeTests
{
    static int checks;
    static void Equal(object actual, object expected, string label)
    { checks++; if (!actual.Equals(expected)) throw new Exception(label + ": " + actual + " != " + expected); }
    static string Reason(bool active=true, bool modifiers=false, uint flags=0, bool captured=false,
        bool own=true, bool current=true, string cls="OrRandomView", int id=0xE900, bool mdi=true, bool inside=true)
    { return OrCADWheelZoom.ScopeReason(active, modifiers, flags, captured, own, current, cls, id, mdi, inside); }
    public static int Main(string[] args)
    {
        // Older .NET can fail formatting a stack trace under a Unicode path.
        try { return Run(args); }
        catch (Exception ex) { Console.Error.WriteLine("FAIL: " + ex.Message); return 1; }
    }
    static int Run(string[] args)
    {
        if (args.Length == 1 && args[0] == "--signals-guard-smoke") {
            for (int request=0; request<3; request++) {
                var observer = new OrCADWheelZoom.SignalsGestureObserver();
                try { Equal(observer.Ready,true,"both temporary observer hooks installed"); }
                finally { observer.Dispose(); }
                Equal(observer.Ready,false,"observer no longer reports healthy after disposal");
                Equal(observer.HasExited,true,"observer thread/message pump exited; no persistent listener");
            }
            Console.WriteLine("PASS: " + checks + " Signals read-only observer lifecycle checks (" + (IntPtr.Size*8)
                + "-bit); no Capture commands or UI input.");
            return 0;
        }
        Equal(Reason(), "eligible", "hover current schematic");
        var mainRoot = new IntPtr(10); var ownedDrawingRoot = new IntPtr(11); var otherRoot = new IntPtr(12);
        Equal(OrCADWheelZoom.ForegroundAllowsDrawing(true,true,ownedDrawingRoot,ownedDrawingRoot,mainRoot,mainRoot,"AfxMDIFrame80"),true,"drawing frame foreground before switching");
        Equal(OrCADWheelZoom.ForegroundAllowsDrawing(true,true,mainRoot,ownedDrawingRoot,mainRoot,mainRoot,"OrCaptureFrame"),true,"return to Capture main frame keeps owned drawing eligible");
        Equal(OrCADWheelZoom.ForegroundAllowsDrawing(true,true,mainRoot,ownedDrawingRoot,mainRoot,mainRoot,"OrCaptureFrame"),true,"repeated reactivation does not latch disabled");
        Equal(OrCADWheelZoom.ForegroundAllowsDrawing(false,true,otherRoot,ownedDrawingRoot,mainRoot,mainRoot,"OrCaptureFrame"),false,"foreign process never allowed even with matching handles");
        Equal(OrCADWheelZoom.ForegroundAllowsDrawing(true,false,mainRoot,ownedDrawingRoot,mainRoot,mainRoot,"OrCaptureFrame"),false,"modal dialog disables owner and drawing");
        Equal(OrCADWheelZoom.ForegroundAllowsDrawing(true,true,otherRoot,ownedDrawingRoot,otherRoot,mainRoot,"OrCaptureFrame"),false,"different Capture window family rejected");
        Equal(OrCADWheelZoom.ForegroundAllowsDrawing(true,true,otherRoot,ownedDrawingRoot,mainRoot,mainRoot,"#32770"),false,"same-owner native dialog is not main frame");
        Equal(OrCADWheelZoom.ForegroundAllowsDrawing(true,true,otherRoot,ownedDrawingRoot,mainRoot,mainRoot,"TkTopLevel"),false,"standalone Tcl dialog must not enable drawing behind it");
        Equal(OrCADWheelZoom.ForegroundAllowsDrawing(true,true,otherRoot,ownedDrawingRoot,mainRoot,mainRoot,"Afx:dialog"),false,"modeless MFC dialog not blindly accepted");
        Equal(OrCADWheelZoom.ForegroundAllowsDrawing(true,true,mainRoot,mainRoot,mainRoot,mainRoot,"OrCaptureFrame"),true,"ordinary parent-root layout unchanged");
        Equal(OrCADWheelZoom.ForegroundAllowsDrawing(true,true,mainRoot,ownedDrawingRoot,IntPtr.Zero,IntPtr.Zero,"OrCaptureFrame"),false,"failed owner query cannot prove ownership");
        Equal(OrCADWheelZoom.ForegroundAllowsDrawing(true,true,IntPtr.Zero,ownedDrawingRoot,mainRoot,mainRoot,"OrCaptureFrame"),false,"lost activation does not match");
        Equal(OrCADWheelZoom.ForegroundAllowsDrawing(true,true,mainRoot,IntPtr.Zero,mainRoot,mainRoot,"OrCaptureFrame"),false,"destroyed drawing does not match");
        Equal(OrCADWheelZoom.NavigationWindowAllowed(2,true,true,true,true,"OrCaptureFrame"),true,"foreground navigation unchanged");
        Equal(OrCADWheelZoom.NavigationWindowAllowed(2,false,false,true,true,"OrCaptureFrame"),true,"wheel/right-drag on visible inactive Capture does not need left click");
        Equal(OrCADWheelZoom.NavigationWindowAllowed(2,true,true,true,true,"OrCaptureFrame"),true,"return by left-click also remains compatible");
        Equal(OrCADWheelZoom.NavigationWindowAllowed(2,false,false,true,true,"OrCaptureFrame"),true,"repeated outside click and hover remains eligible");
        Equal(OrCADWheelZoom.NavigationWindowAllowed(0,false,false,true,true,"OrCaptureFrame"),false,"disabled tool does not enable background navigation");
        Equal(OrCADWheelZoom.NavigationWindowAllowed(1,false,false,true,true,"OrCaptureFrame"),false,"legacy focused controller remains foreground-only");
        Equal(OrCADWheelZoom.NavigationWindowAllowed(2,false,false,false,true,"OrCaptureFrame"),false,"other process under pointer is never remapped");
        Equal(OrCADWheelZoom.NavigationWindowAllowed(2,false,false,true,false,"OrCaptureFrame"),false,"hidden/disabled/modal-owner drawing is blocked");
        Equal(OrCADWheelZoom.NavigationWindowAllowed(2,false,false,true,true,"#32770"),false,"background dialog root is not Capture main frame");
        Equal(OrCADWheelZoom.NavigationWindowAllowed(2,false,false,true,true,"TkTopLevel"),false,"background standalone Tcl window excluded");
        Equal(OrCADWheelZoom.NavigationWindowAllowed(2,true,false,true,true,"OrCaptureFrame"),false,"foreground Capture popup cannot use inactive exception");
        Equal(OrCADWheelZoom.NavigationWindowAllowed(2,true,true,false,true,"OrCaptureFrame"),false,"wrong bound process rejected even if ownership predicate matches");
        Equal(Reason(current:false),"not-current-page-or-query-timeout","background window policy does not bypass current MDI page guard");
        Equal(Reason(cls:"SysTreeView32"),"not-capture-drawing-view","background window policy does not enable project tree");
        Equal(Reason(flags:4),"menu-dialog-or-drag","background window policy does not bypass Capture menu guard");
        Equal(Reason(flags:1), "eligible", "caret blink is not a menu");
        Equal(Reason(active:false), "controller-disabled-or-stale", "controller stale");
        Equal(Reason(modifiers:true), "modifier-or-button-held", "Ctrl/Shift/Alt/mouse buttons");
        foreach (int key in new int[] {0x10,0x11,0x12,0x5B,0x5C}) {
            Equal(OrCADWheelZoom.ScopeInputBlocks(key,false,false),true,"wheel still blocks keyboard modifiers");
            Equal(OrCADWheelZoom.ScopeInputBlocks(key,true,false),true,"pan still blocks keyboard modifiers");
            Equal(OrCADWheelZoom.ScopeInputBlocks(key,false,true),false,"Signals allows initial shortcut modifiers without release wait");
        }
        foreach (int key in new int[] {1,2,4,5,6}) {
            Equal(OrCADWheelZoom.ScopeInputBlocks(key,false,true),true,"Signals still blocks held mouse buttons");
            Equal(OrCADWheelZoom.ScopeInputBlocks(key,false,false),true,"wheel mouse-button guard unchanged");
        }
        Equal(OrCADWheelZoom.ScopeInputBlocks(2,true,false),false,"pan start still permits its own right-down");
        Equal(Reason(captured:true), "menu-dialog-or-drag", "drag");
        Equal(Reason(flags:4), "menu-dialog-or-drag", "menu");
        Equal(Reason(own:false), "hit-outside-capture", "Chrome must not fall back to focus");
        Equal(Reason(current:false), "not-current-page-or-query-timeout", "inactive page or timeout");
        Equal(OrCADWheelZoom.StateMode("hover 0",true),2,"RichEdit focus must not disable hover");
        Equal(OrCADWheelZoom.StateMode("hover 1",true),2,"drawing focus hover");
        Equal(OrCADWheelZoom.StateMode("hover 0",false),0,"stale controller disables hover");
        Equal(OrCADWheelZoom.StateMode("0",true),0,"disable command");
        Equal(OrCADWheelZoom.StateMode("1",true),1,"legacy module keeps focused mode");
        Equal(OrCADWheelZoom.StateMode("hover corrupt",true),0,"corrupt state disables hover");
        Equal(OrCADWheelZoom.RetainedStateMode("",true,2),2,"fresh truncate overlap retains hover lease");
        Equal(OrCADWheelZoom.RetainedStateMode(" \r\n",true,1),1,"fresh whitespace overlap retains legacy lease");
        Equal(OrCADWheelZoom.RetainedStateMode("",false,2),0,"empty stale file must disable");
        Equal(OrCADWheelZoom.RetainedStateMode("0",true,2),0,"explicit off is immediate despite retained lease");
        Equal(OrCADWheelZoom.RetainedStateMode("bad state",true,2),0,"invalid nonempty text is not a write overlap");
        Equal(OrCADWheelZoom.RetainedStateMode("hover 0",true,0),2,"valid write resumes hover after pause");
        Equal(Reason(cls:"RichEdit20A"), "not-capture-drawing-view", "command window");
        Equal(Reason(cls:"AfxWnd80", id:260), "not-capture-drawing-view", "toolbar observed in log");
        Equal(Reason(cls:"SysTreeView32"), "not-capture-drawing-view", "project tree");
        Equal(Reason(cls:"Afx:test"), "not-capture-drawing-view", "unverified generic MFC window");
        Equal(Reason(cls:"Chrome_RenderWidgetHostHWND"), "not-capture-drawing-view", "browser");
        Equal(Reason(mdi:false), "not-mdi-view", "dialog view");
        Equal(Reason(inside:false), "outside-client-area", "scrollbar");
        Equal(Reason(id:260), "not-capture-drawing-view", "wrong control ID");
        var pan = new OrCADWheelZoom.PanGesture();
        Equal(pan.Mode, 0, "no pan before right-down");
        Equal(pan.Move(100,100,6), false, "move without down is not pan");
        pan.Begin(-100,200);
        Equal(pan.Move(-95,205,6), false, "minor hand shake remains a click");
        Equal(pan.Release(), 1, "pending release replays a right click");
        Equal(pan.Mode, 0, "right click resets gesture");
        pan.Begin(-100,200);
        Equal(pan.Move(-106,200,6), true, "leftward threshold starts pan");
        Equal(pan.Move(-150,100,6), false, "grab initialized once only");
        Equal(pan.Release(), 2, "drag release stops view changes, not context menu");
        pan.Begin(10,10);
        Equal(pan.Move(10,16,6), true, "vertical drag starts pan");
        pan.Cancel();
        Equal(pan.Move(100,100,6), false, "cancelled gesture cannot restart on movement");
        Equal(pan.Release(), 3, "cancelled right-up must be consumed");
        Equal(pan.Release(), 0, "repeated release must not restart scrolling");
        pan.Begin(10,10); pan.Cancel(); pan.Begin(20,20);
        Equal(pan.Mode, 1, "new down resynchronizes after missed up");
        Equal(pan.Release(), 1, "new right click after cancelled drag");
        Equal(OrCADWheelZoom.GrabPosition(1000,0,4999,1000,1000,100),900,"sheet follows pointer right");
        Equal(OrCADWheelZoom.GrabPosition(1000,0,4999,1000,1000,-100),1100,"sheet follows pointer left");
        Equal(OrCADWheelZoom.GrabPosition(1000,0,4999,500,500,70),930,"vertical grab in logical DPI units");
        Equal(OrCADWheelZoom.GrabPosition(300,0,1999,200,1000,100),280,"non-pixel scrollbar units");
        Equal(OrCADWheelZoom.GrabPosition(100,0,4999,1000,1000,200),0,"clamp at upper-left boundary");
        Equal(OrCADWheelZoom.GrabPosition(3900,0,4999,1000,1000,-200),4000,"clamp at maximum minus visible page");
        Equal(OrCADWheelZoom.GrabPosition(20,10,100,0,100,-300),100,"zero page fallback and nonzero minimum");
        Equal(OrCADWheelZoom.GrabPosition(50,10,100,200,100,0),10,"oversized visible page must not underflow");
        Equal(OrCADWheelZoom.GrabPosition(1000,0,Int32.MaxValue,1000,1000,Int64.MinValue),2147482648,"large delta clamps without overflow");
        Equal(OrCADWheelZoom.GrabPosition(1000,0,4999,1000,1000,0),1000,"stationary pointer leaves position unchanged");
        Equal(OrCADWheelZoom.LiveScrollCommand,5,"real-time drag notification, not release-only code 4");
        Equal(OrCADWheelZoom.ScrollParameter(65535,OrCADWheelZoom.LiveScrollCommand) & 0xFFFF,5,"live position command");
        Equal((uint)OrCADWheelZoom.ScrollParameter(65535,5) >> 16,65535u,"full unsigned thumb position");
        bool scrollRejected = false;
        try {OrCADWheelZoom.ScrollParameter(65536,4);} catch (ArgumentOutOfRangeException) {scrollRejected=true;}
        Equal(scrollRejected,true,"large scroll position must never wrap to page start");
        var view = new IntPtr(100); var frame = new IntPtr(200); var bar = new IntPtr(300);
        var routes = OrCADWheelZoom.ScrollRoutes(view,frame,bar);
        Equal(routes.Length,2,"drawing and its own frame only");
        Equal(routes[0].Target,view,"drawing handles live view movement before frame");
        Equal(routes[0].Control,bar,"shared scrollbar handle preserved");
        Equal(OrCADWheelZoom.ScrollRoutes(view,view,IntPtr.Zero).Length,1,"no duplicate same-window route");
        OrCADWheelZoom.ScrollRoute selected;
        int attempts=0;
        bool routed = OrCADWheelZoom.FindScrollRoute(routes,397,delegate(OrCADWheelZoom.ScrollRoute route,int desired) {
            attempts++; Equal(desired,397,"requested position survives routing");
            return route.Target == view ? OrCADWheelZoom.ScrollResult.Applied : OrCADWheelZoom.ScrollResult.Unchanged;
        },out selected);
        Equal(routed,true,"view-only handler responds even when frame ignores messages");
        Equal(selected.Target,view,"responsive handler cached");
        Equal(attempts,1,"do not send twice after movement");
        attempts=0;
        routed=OrCADWheelZoom.FindScrollRoute(routes,397,delegate(OrCADWheelZoom.ScrollRoute route,int desired) {
            attempts++;
            return route.Target == frame ? OrCADWheelZoom.ScrollResult.Applied : OrCADWheelZoom.ScrollResult.Unchanged;
        },out selected);
        Equal(routed,true,"unchanged drawing route can use its frame");
        Equal(selected.Target,frame,"responsive frame cached");
        Equal(attempts,2,"one fallback after verified unchanged position");
        foreach (var failure in new OrCADWheelZoom.ScrollResult[] {OrCADWheelZoom.ScrollResult.Failed,OrCADWheelZoom.ScrollResult.UnexpectedPosition}) {
            attempts=0;
            routed=OrCADWheelZoom.FindScrollRoute(routes,397,delegate(OrCADWheelZoom.ScrollRoute route,int desired) {
                attempts++; return failure;
            },out selected);
            Equal(routed,false,"timeout/wrong position is not success");
            Equal(attempts,1,"no retry after uncertain movement");
            Equal(selected==null,true,"failed route never cached");
        }
        routed=OrCADWheelZoom.FindScrollRoute(routes,397,delegate(OrCADWheelZoom.ScrollRoute route,int desired) {
            return OrCADWheelZoom.ScrollResult.Unchanged;
        },out selected);
        Equal(routed,false,"ignored messages must not claim pan success");
        Equal(OrCADWheelZoom.ScrollbarUsable(true,true),true,"enabled live scrollbar");
        Equal(OrCADWheelZoom.ScrollbarUsable(false,true),false,"disabled scrollbar with stale nonzero range");
        Equal(OrCADWheelZoom.ScrollbarUsable(true,false),false,"hidden control is not scrollable");
        Equal(OrCADWheelZoom.WheelBlockedByPan(0),false,"normal wheel unchanged");
        Equal(OrCADWheelZoom.WheelBlockedByPan(1),true,"pending physical right gesture");
        Equal(OrCADWheelZoom.WheelBlockedByPan(2),true,"active drag does not zoom");
        Equal(OrCADWheelZoom.WheelBlockedByPan(3),false,"cancelled/missed right-up must not permanently block wheel");
        Equal(OrCADWheelZoom.MouseMessageRelevant(0x020A,0),true,"wheel reaches routing independently of input-origin flags");
        Equal(OrCADWheelZoom.MouseMessageRelevant(0x0204,0),true,"right-down reaches routing");
        Equal(OrCADWheelZoom.MouseMessageRelevant(0x0205,3),true,"right-up clears cancelled gesture");
        Equal(OrCADWheelZoom.MouseMessageRelevant(0x0200,0),false,"idle mouse move retains fast pass-through");
        Equal(OrCADWheelZoom.MouseMessageRelevant(0x0200,2),true,"software and hardware drag moves share routing");
        Equal(OrCADWheelZoom.MouseMessageRelevant(0x0201,0),false,"idle left-button remains unchanged");
        Equal(OrCADWheelZoom.MouseMessageRelevant(0x0201,2),true,"additional button cancels active drag");
        Equal(OrCADWheelZoom.IsOwnRightClick(0x0204,OrCADWheelZoom.RightClickTag),true,"own replay down cannot start another pan");
        Equal(OrCADWheelZoom.IsOwnRightClick(0x0205,OrCADWheelZoom.RightClickTag),true,"own replay up reaches native Capture");
        Equal(OrCADWheelZoom.IsOwnRightClick(0x020A,OrCADWheelZoom.RightClickTag),false,"tag does not exempt unrelated wheel");
        Equal(OrCADWheelZoom.IsOwnRightClick(0x0204,UIntPtr.Zero),false,"ordinary right click still enters gesture detection");
        Equal(OrCADWheelZoom.IsOwnRightClick(0x0204,new UIntPtr(123u)),false,"other injected/remote inputs still work");
        var clickInputs = OrCADWheelZoom.RightClickInputs(false);
        Equal(clickInputs.Length,2,"right click is one ordered pair");
        Equal(clickInputs[0].Mouse.Flags,8u,"right down only, no MOVE/ABSOLUTE flags");
        Equal(clickInputs[1].Mouse.Flags,16u,"right up only, no coordinate transfer");
        foreach (var input in clickInputs) {
            Equal(input.Type,0u,"no keyboard injection");
            Equal(input.Mouse.X,0,"no cursor x relocation");
            Equal(input.Mouse.Y,0,"no cursor y relocation");
            Equal(input.Mouse.Data,0u,"no wheel injection");
            Equal(input.Mouse.Time,0u,"Windows supplies timestamp");
            Equal(input.Mouse.Extra,OrCADWheelZoom.RightClickTag,"pair shares recursion guard");
        }
        uint clickInserted, clickCleanup; int clickCalls=0;
        Equal(OrCADWheelZoom.ReplayRightClick(delegate(OrCADWheelZoom.NativeInput[] inputs) {clickCalls++; return (uint)inputs.Length;},
            out clickInserted,out clickCleanup),true,"full pair accepted");
        Equal(clickCalls,1,"successful click never duplicated");
        Equal(clickInserted,2u,"full insert count");
        Equal(clickCleanup,0u,"successful pair needs no extra up");
        clickCalls=0;
        Equal(OrCADWheelZoom.ReplayRightClick(delegate(OrCADWheelZoom.NativeInput[] inputs) {
            clickCalls++;
            if (clickCalls==2) {Equal(inputs.Length,1,"partial down cleanup has one event"); Equal(inputs[0].Mouse.Flags,16u,"partial insertion pairs only up");}
            return 1;
        },out clickInserted,out clickCleanup),false,"partial insertion not claimed success");
        Equal(clickCalls,2,"partial insertion attempts release once");
        Equal(clickCleanup,1u,"release inserted");
        clickCalls=0;
        Equal(OrCADWheelZoom.ReplayRightClick(delegate(OrCADWheelZoom.NativeInput[] inputs) {clickCalls++; return 0;},
            out clickInserted,out clickCleanup),false,"blocked injection remains failure");
        Equal(clickCalls,1,"blocked input is not repeatedly injected");
        Equal(clickCleanup,0u,"no down means no cleanup needed");
        Equal(OrCADWheelZoom.ClickReplayStillCurrent(-100,200,-95,195,16,0),true,"small hand shake and negative monitor origin accepted");
        Equal(OrCADWheelZoom.ClickReplayStillCurrent(-100,200,-94,200,16,0),false,"pointer moved beyond click threshold: do not click elsewhere");
        Equal(OrCADWheelZoom.ClickReplayStillCurrent(100,200,100,206,16,0),false,"vertical pointer movement cancels replay");
        Equal(OrCADWheelZoom.ClickReplayStillCurrent(100,200,100,200,251,0),false,"stale delayed click discarded");
        Equal(OrCADWheelZoom.ClickReplayStillCurrent(100,200,100,200,250,0),true,"maximum replay age allowed");
        Equal(OrCADWheelZoom.ClickReplayStillCurrent(100,200,100,200,-1,0),false,"clock anomaly discards click");
        foreach (int mode in new int[] {1,2,3})
            Equal(OrCADWheelZoom.ClickReplayStillCurrent(100,200,100,200,16,mode),false,"another gesture prevents replay");
        Equal(OrCADWheelZoom.ClickReplayStillCurrent(Int32.MinValue,200,Int32.MaxValue,200,16,0),false,"distance check cannot overflow");
        var watchdog = new OrCADWheelZoom.InputWatchdog();
        Equal(watchdog.Sample(0,0,0,true),false,"first sample does not rearm");
        Equal(watchdog.Sample(0,0,0,true),false,"idle is not a failed input hook");
        Equal(watchdog.Sample(10,0,1,true),false,"healthy mouse movement with callbacks");
        Equal(watchdog.Sample(20,0,1,true),false,"single stale sample is insufficient");
        Equal(watchdog.Sample(30,0,1,true),true,"repeated physical motion without callbacks rearms hook");
        Equal(watchdog.Sample(40,0,2,true),false,"resumed callbacks stop recovery");
        Equal(watchdog.Sample(50,0,2,false),false,"another foreground app is not a recovery trigger");
        Equal(watchdog.Sample(60,0,2,false),false,"continued outside motion ignored");
        Equal(watchdog.Sample(70,0,2,true),false,"returning to Capture starts a new audit");
        Equal(watchdog.Sample(70,0,2,true),false,"stationary cursor resets stale-motion audit");
        int verticalCalls=0;
        bool continued=OrCADWheelZoom.MoveBothAxes(delegate { return OrCADWheelZoom.AxisResult.Unavailable; },delegate {
            verticalCalls++; return OrCADWheelZoom.AxisResult.Applied;
        });
        Equal(continued,true,"fitted horizontal axis does not cancel vertical pan");
        Equal(verticalCalls,1,"vertical movement must still run after blocked horizontal axis");
        continued=OrCADWheelZoom.MoveBothAxes(delegate { return OrCADWheelZoom.AxisResult.Applied; },delegate {
            return OrCADWheelZoom.AxisResult.Unavailable;
        });
        Equal(continued,true,"fitted vertical axis does not cancel horizontal pan");
        continued=OrCADWheelZoom.MoveBothAxes(delegate { return OrCADWheelZoom.AxisResult.Unavailable; },delegate {
            return OrCADWheelZoom.AxisResult.Unavailable;
        });
        Equal(continued,true,"both axes at bounds is not an unsafe result");
        verticalCalls=0;
        continued=OrCADWheelZoom.MoveBothAxes(delegate { return OrCADWheelZoom.AxisResult.Unsafe; },delegate {
            verticalCalls++; return OrCADWheelZoom.AxisResult.Applied;
        });
        Equal(continued,false,"uncertain timeout stops whole gesture");
        Equal(verticalCalls,0,"no further scrolling after uncertain result");
        continued=OrCADWheelZoom.MoveBothAxes(delegate { return OrCADWheelZoom.AxisResult.Idle; },delegate {
            return OrCADWheelZoom.AxisResult.Unsafe;
        });
        Equal(continued,false,"vertical uncertainty also stops gesture");
        foreach (int delta in new int[] {-120,120,60,-60,240}) {
            int w = OrCADWheelZoom.WheelParameter(unchecked((uint)(delta << 16)) | 0xFFFFu);
            Equal((int)(short)(w >> 16), delta, "signed wheel delta");
            Equal(w & 0xFFFF, 8, "Ctrl flag only");
        }
        foreach (int x in new int[] {-32768,-1920,-1,0,1920,32767})
            foreach (int y in new int[] {-1080,-1,0,1080}) {
                int p = OrCADWheelZoom.PointParameter(x,y);
                Equal((int)(short)p, x, "signed multi-monitor X");
                Equal((int)(short)(p >> 16), y, "signed multi-monitor Y");
            }
        bool rejected = false;
        try { OrCADWheelZoom.PointParameter(32768,0); } catch (ArgumentOutOfRangeException) { rejected=true; }
        Equal(rejected,true,"oversize desktop must not wrap coordinates");
        Equal(OrCADWheelZoom.SignalsLaunchReady(null),false,"no launch handshake: no input");
        Equal(OrCADWheelZoom.SignalsLaunchReady(""),false,"partial launch marker: no input");
        Equal(OrCADWheelZoom.SignalsLaunchReady("capture-ready-v17"),true,"matching launcher readiness");
        Equal(OrCADWheelZoom.SignalsLaunchReady("context-ready"),false,"old protocol must not inject input");
        Equal(OrCADWheelZoom.SignalsLaunchReady("capture-ready-v17\n"),false,"malformed marker rejected");
        Type mouse = typeof(OrCADWheelZoom).GetNestedType("MouseData",BindingFlags.NonPublic);
        Equal(Marshal.OffsetOf(mouse,"Data").ToInt32(),8,"wheel struct offset");
        Equal(Marshal.OffsetOf(mouse,"Extra").ToInt32(),IntPtr.Size==8?24:20,"pointer alignment");
        Equal(Marshal.SizeOf(mouse),IntPtr.Size==8?32:24,"mouse struct size");
        Type gui = typeof(OrCADWheelZoom).GetNestedType("GuiInfo",BindingFlags.NonPublic);
        Equal(Marshal.SizeOf(gui),IntPtr.Size==8?72:48,"GUI struct size");
        Type scroll = typeof(OrCADWheelZoom).GetNestedType("SCROLLINFO",BindingFlags.NonPublic);
        Equal(Marshal.SizeOf(scroll),28,"SCROLLINFO size on both bitnesses");
        Equal(Marshal.OffsetOf(typeof(OrCADWheelZoom.MouseInput),"Extra").ToInt32(),IntPtr.Size==8?24:20,"MOUSEINPUT pointer alignment");
        Equal(Marshal.SizeOf(typeof(OrCADWheelZoom.MouseInput)),IntPtr.Size==8?32:24,"MOUSEINPUT native size");
        Equal(Marshal.OffsetOf(typeof(OrCADWheelZoom.NativeInput),"Mouse").ToInt32(),IntPtr.Size==8?8:4,"INPUT native union alignment");
        Equal(Marshal.SizeOf(typeof(OrCADWheelZoom.NativeInput)),IntPtr.Size==8?40:28,"SendInput cbSize on both bitnesses");
        // Hold a concurrent writer open. Reading state must not deny its access.
        string stateTest = Path.Combine(Path.GetTempPath(), "OrCADStateShare-" + Guid.NewGuid().ToString("N") + ".state");
        FieldInfo stateField = typeof(OrCADWheelZoom).GetField("statePath",BindingFlags.Static|BindingFlags.NonPublic);
        object previousPath = stateField.GetValue(null);
        try {
            File.WriteAllText(stateTest,"hover 1");
            stateField.SetValue(null,stateTest);
            using (var writer = new FileStream(stateTest,FileMode.Open,FileAccess.Write,FileShare.ReadWrite|FileShare.Delete)) {
                MethodInfo readState = typeof(OrCADWheelZoom).GetMethod("ReadControllerState",BindingFlags.Static|BindingFlags.NonPublic);
                Equal((string)readState.Invoke(null,null),"hover 1","controller read coexists with writer handle");
            }
        } finally { stateField.SetValue(null,previousPath); File.Delete(stateTest); }
        Equal(OrCADWheelZoom.SignalsMenuItemAllowed(14844,0,IntPtr.Zero),true,"enabled native Signals item");
        Equal(OrCADWheelZoom.SignalsMenuItemAllowed(14844,1,IntPtr.Zero),false,"grayed Signals cannot dispatch");
        Equal(OrCADWheelZoom.SignalsMenuItemAllowed(14844,2,IntPtr.Zero),false,"disabled Signals cannot dispatch");
        Equal(OrCADWheelZoom.SignalsMenuItemAllowed(14843,0,IntPtr.Zero),false,"different command cannot dispatch");
        Equal(OrCADWheelZoom.SignalsMenuItemAllowed(14844,0,new IntPtr(1)),false,"submenu cannot dispatch");
        Equal(OrCADWheelZoom.SignalsMenuItemAllowed(14844,8,IntPtr.Zero),true,"checked enabled item");
        Equal(Marshal.SizeOf(typeof(OrCADWheelZoom.MenuBarInfo)),IntPtr.Size==8?48:32,"MENUBARINFO native size");
        Equal(Marshal.OffsetOf(typeof(OrCADWheelZoom.MenuBarInfo),"Menu").ToInt32(),IntPtr.Size==8?24:20,"MENUBARINFO pointer alignment");
        Equal(Marshal.OffsetOf(typeof(OrCADWheelZoom.MenuBarInfo),"Flags").ToInt32(),IntPtr.Size==8?40:28,"MENUBARINFO flags alignment");
        Equal(Marshal.SizeOf(typeof(OrCADWheelZoom.MenuItemInfo)),IntPtr.Size==8?80:48,"MENUITEMINFO native size");
        Equal(Marshal.OffsetOf(typeof(OrCADWheelZoom.MenuItemInfo),"SubMenu").ToInt32(),IntPtr.Size==8?24:20,"MENUITEMINFO pointer alignment");
        foreach (string name in new string[] {"Signals", "&Signals", " signals ", "Signals\tAlt+S"})
            Equal(OrCADWheelZoom.SignalsAccessibleItemAllowed(name,12,0),true,"exact enabled Signals menu label");
        foreach (string name in new string[] {null, "", "No Signals", "Signals navigation", "Signal", "Edit Properties"})
            Equal(OrCADWheelZoom.SignalsAccessibleItemAllowed(name,12,0),false,"unrelated or partial label rejected");
        foreach (int state in new int[] {1,0x8000,0x10000,0x40000000,1|4})
            Equal(OrCADWheelZoom.SignalsAccessibleItemAllowed("Signals",12,state),false,"unavailable/hidden/offscreen/submenu rejected");
        Equal(OrCADWheelZoom.SignalsAccessibleItemAllowed("Signals",12,4),true,"focused Signals menu item allowed");
        Equal(OrCADWheelZoom.SignalsAccessibleItemAllowed("Signals",12,2),true,"selected Signals menu item allowed");
        Equal(OrCADWheelZoom.SignalsPopupScopeAllowed(true,true,true,true),true,"owned popup in drawing thread");
        Equal(OrCADWheelZoom.SignalsPopupScopeAllowed(true,true,true,false),true,"owned popup in separate menu thread");
        Equal(OrCADWheelZoom.SignalsPopupScopeAllowed(true,true,false,true),true,"ownerless popup in exact drawing thread");
        Equal(OrCADWheelZoom.SignalsPopupScopeAllowed(true,true,false,false),false,"unrelated Capture window rejected");
        Equal(OrCADWheelZoom.SignalsPopupScopeAllowed(false,true,true,true),false,"foreign process rejected");
        Equal(OrCADWheelZoom.SignalsPopupScopeAllowed(true,false,true,true),false,"hidden window rejected");
        Equal(OrCADWheelZoom.SignalsPopupScopeAllowed(false,true,false,true),false,"thread alone cannot authorize foreign process");
        Equal(OrCADWheelZoom.SignalsPopupScopeAllowed(true,false,false,true),false,"thread alone cannot authorize hidden popup");
        foreach (int role in new int[] {0,9,11,43})
            Equal(OrCADWheelZoom.SignalsAccessibleItemAllowed("Signals",role,0),false,"non-menu item cannot invoke");
        Equal(OrCADWheelZoom.SignalsPopupStyleAllowed(0x80000000u),true,"plain popup style accepted");
        Equal(OrCADWheelZoom.SignalsPopupStyleAllowed(0x80800000u),true,"bordered MFC popup accepted");
        Equal(OrCADWheelZoom.SignalsPopupStyleAllowed(0x80C00000u),false,"captioned floating pane rejected");
        Equal(OrCADWheelZoom.SignalsPopupStyleAllowed(0x80080000u),false,"system-menu dialog rejected");
        Equal(OrCADWheelZoom.SignalsPopupStyleAllowed(0xC0000000u),false,"child window rejected");
        Equal(OrCADWheelZoom.SignalsPopupStyleAllowed(0x00800000u),false,"non-popup window rejected");
        foreach (string cls in new string[] {"#32768", "Afx:popup-menu", "AfxWnd140"})
            Equal(OrCADWheelZoom.SignalsCleanupTargetAllowed(true,true,true,false,cls),true,"matched new standard/MFC popup may close");
        foreach (string cls in new string[] {null, "", "#32770", "OrCaptureFrame", "OrRandomView", "SysTreeView32", "SysShadow"})
            Equal(OrCADWheelZoom.SignalsCleanupTargetAllowed(true,true,true,false,cls),false,"unverified non-menu class never closes");
        Equal(OrCADWheelZoom.SignalsCleanupTargetAllowed(false,true,true,false,"#32768"),false,"pre-existing popup untouched");
        Equal(OrCADWheelZoom.SignalsCleanupTargetAllowed(true,false,true,false,"#32768"),false,"foreign popup untouched");
        Equal(OrCADWheelZoom.SignalsCleanupTargetAllowed(true,true,false,false,"AfxWnd140"),false,"child/result control untouched");
        Equal(OrCADWheelZoom.SignalsCleanupTargetAllowed(true,true,true,true,"AfxWnd140"),false,"main frame/drawing root untouched");
        Equal(OrCADWheelZoom.SignalsCleanupEligibility(false,false,false,false,false),OrCADWheelZoom.SignalsCleanupProbe.Gone,"invisible/destroyed popup needs no messages");
        Equal(OrCADWheelZoom.SignalsCleanupEligibility(true,true,true,true,true),OrCADWheelZoom.SignalsCleanupProbe.Safe,"unchanged exact popup may close");
        Equal(OrCADWheelZoom.SignalsCleanupEligibility(true,false,true,true,true),OrCADWheelZoom.SignalsCleanupProbe.Unsafe,"changed handle/class/thread/owner rejected");
        Equal(OrCADWheelZoom.SignalsCleanupEligibility(true,true,false,true,true),OrCADWheelZoom.SignalsCleanupProbe.Unsafe,"unproven target rejected");
        Equal(OrCADWheelZoom.SignalsCleanupEligibility(true,true,true,false,true),OrCADWheelZoom.SignalsCleanupProbe.Unsafe,"foreground/page/modal change stops cleanup");
        Equal(OrCADWheelZoom.SignalsCleanupEligibility(true,true,true,true,false),OrCADWheelZoom.SignalsCleanupProbe.Unsafe,"new mouse/key input stops cleanup");
        foreach (uint tag in new uint[] {0u,123u,0x4F435251u})
            Equal(OrCADWheelZoom.SignalsGestureMessage(false,0x0200,new UIntPtr(tag)),false,"hover never cancels cleanup");
        foreach (int msg in new int[] {0x0201,0x0202,0x0203,0x0204,0x0205,0x0206,0x0207,0x0208,0x0209,0x020A,0x020B,0x020C,0x020D,0x020E})
            Equal(OrCADWheelZoom.SignalsGestureMessage(false,msg,UIntPtr.Zero),true,"click/double-click/wheel/extra button cancels cleanup");
        foreach (int msg in new int[] {0x0204,0x0205}) {
            Equal(OrCADWheelZoom.SignalsGestureMessage(false,msg,OrCADWheelZoom.RightClickTag),false,"own popup replay is not user cancellation");
            Equal(OrCADWheelZoom.SignalsGestureMessage(false,msg,new UIntPtr(123u)),true,"driver/remote right-click remains cancellation");
        }
        Equal(OrCADWheelZoom.SignalsGestureMessage(false,0x0201,OrCADWheelZoom.RightClickTag),true,"tag does not exempt unrelated left-click");
        foreach (int msg in new int[] {0x0100,0x0101,0x0104,0x0105})
            Equal(OrCADWheelZoom.SignalsGestureMessage(true,msg,UIntPtr.Zero),true,"keyboard edges are candidates; state distinguishes shortcut release");
        Equal(OrCADWheelZoom.SignalsGestureMessage(true,0x0200,UIntPtr.Zero),false,"unrelated keyboard callback message ignored");
        var gesture = new OrCADWheelZoom.SignalsGestureState();
        int checkpoint = gesture.Generation;
        for (int i=0; i<100; i++) gesture.Observe(false,0x0200,UIntPtr.Zero);
        Equal(gesture.Unchanged(checkpoint),true,"continuous menu hover preserves checkpoint");
        gesture.Observe(false,0x0204,OrCADWheelZoom.RightClickTag);
        gesture.Observe(false,0x0205,OrCADWheelZoom.RightClickTag);
        Equal(gesture.Unchanged(checkpoint),true,"tagged popup opening preserves checkpoint");
        gesture.Observe(false,0x0201,UIntPtr.Zero);
        gesture.Observe(false,0x0202,UIntPtr.Zero);
        Equal(gesture.Unchanged(checkpoint),false,"fast click remains latched after button released");
        Equal(gesture.Generation,checkpoint+2,"each button edge counted");
        checkpoint = gesture.Generation;
        gesture.Observe(true,0x0100,UIntPtr.Zero);
        gesture.Observe(true,0x0101,UIntPtr.Zero);
        Equal(gesture.Unchanged(checkpoint),false,"fast key remains latched after release");
        foreach (int[] held in new int[][] {new int[] {0x12,0x53},new int[] {0x11,0x71},new int[] {0xA2,0x71},
            new int[] {0x10,0x11,0x71},new int[] {0xA0,0xA2,0x71},new int[] {0x12,0x77}}) {
            gesture = new OrCADWheelZoom.SignalsGestureState();
            gesture.SeedHeldKeys(delegate(int key) { return Array.IndexOf(held,key) >= 0; });
            checkpoint = gesture.Generation;
            foreach (int key in held) gesture.ObserveKeyboard(0x0100,key);
            Equal(gesture.Unchanged(checkpoint),true,"original shortcut autorepeat is tolerated");
            foreach (int key in held) gesture.ObserveKeyboard(0x0101,key);
            Equal(gesture.Unchanged(checkpoint),true,"original shortcut release is tolerated");
            gesture.ObserveKeyboard(0x0100,held[held.Length-1]);
            Equal(gesture.Unchanged(checkpoint),false,"same shortcut key pressed again is a new operation");
        }
        gesture = new OrCADWheelZoom.SignalsGestureState();
        gesture.SeedHeldKeys(delegate(int key) { return key==0x12; });
        gesture.ObserveKeyboard(0x0104,0x12); gesture.ObserveKeyboard(0x0105,0x12);
        Equal(gesture.Generation,0,"initial Alt system-key repeat/up is ignored");
        gesture.ObserveKeyboard(0x0104,0x12);
        Equal(gesture.Generation,1,"new Alt system-key down is not ignored");
        gesture = new OrCADWheelZoom.SignalsGestureState();
        gesture.SeedHeldKeys(delegate(int key) { return key==0x11 || key==0x71; });
        gesture.ObserveKeyboard(0x0100,0x41); gesture.ObserveKeyboard(0x0101,0x41);
        Equal(gesture.Generation,2,"different key while initial Ctrl held remains cancellation");
        gesture.ObserveKeyboard(0x0100,0x1B);
        Equal(gesture.Generation,3,"new Escape still cancels");
        gesture = new OrCADWheelZoom.SignalsGestureState();
        gesture.SeedHeldKeys(delegate(int key) { return key==0x1B; });
        gesture.ObserveKeyboard(0x0101,0x1B);
        Equal(gesture.Generation,1,"Escape during observer setup cannot be excused as an initial shortcut");
        var cleanupMessages = new System.Collections.Generic.List<uint>();
        int cleanupDelay = 0;
        var cleanupResult = OrCADWheelZoom.FinishSignalsPopup(
            delegate { return OrCADWheelZoom.SignalsCleanupProbe.Gone; },
            delegate(uint msg) {cleanupMessages.Add(msg);}, delegate(int ms) {cleanupDelay += ms;});
        Equal(cleanupResult,OrCADWheelZoom.SignalsCleanupResult.Closed,"16.6 already-closed path");
        Equal(cleanupMessages.Count,0,"16.6 adds no cancel/Escape messages");
        Equal(cleanupDelay,0,"16.6 already-closed path adds no delay");
        cleanupDelay = 0;
        cleanupResult = OrCADWheelZoom.FinishSignalsPopup(
            delegate {return cleanupDelay >= 20 ? OrCADWheelZoom.SignalsCleanupProbe.Gone : OrCADWheelZoom.SignalsCleanupProbe.Safe;},
            delegate(uint msg) {cleanupMessages.Add(msg);}, delegate(int ms) {cleanupDelay += ms;});
        Equal(cleanupResult,OrCADWheelZoom.SignalsCleanupResult.Closed,"asynchronous dismissal confirmed without retry");
        Equal(cleanupMessages.Count,1,"still-open popup receives immediate cancel rather than grace wait");
        Equal(cleanupDelay,20,"native asynchronous close still observed");
        cleanupMessages.Clear(); cleanupDelay=0;
        bool popupVisible = true;
        cleanupResult = OrCADWheelZoom.FinishSignalsPopup(
            delegate {return popupVisible ? OrCADWheelZoom.SignalsCleanupProbe.Safe : OrCADWheelZoom.SignalsCleanupProbe.Gone;},
            delegate(uint msg) {Equal(cleanupDelay,0,"no grace before cancel"); cleanupMessages.Add(msg); popupVisible=false;}, delegate(int ms) {});
        Equal(cleanupResult,OrCADWheelZoom.SignalsCleanupResult.Closed,"residual popup closes after cancel");
        Equal(cleanupMessages.Count,1,"cancel sent only once");
        Equal(cleanupMessages[0],OrCADWheelZoom.SignalsCancelMessage,"cancel before Escape");
        cleanupMessages.Clear(); popupVisible=true;
        cleanupResult = OrCADWheelZoom.FinishSignalsPopup(
            delegate {return popupVisible ? OrCADWheelZoom.SignalsCleanupProbe.Safe : OrCADWheelZoom.SignalsCleanupProbe.Gone;},
            delegate(uint msg) {cleanupMessages.Add(msg); if(msg==OrCADWheelZoom.SignalsEscapeMessage) popupVisible=false;}, delegate(int ms) {});
        Equal(cleanupResult,OrCADWheelZoom.SignalsCleanupResult.Closed,"custom menu Escape fallback closes");
        Equal(cleanupMessages.Count,2,"custom menu gets two bounded messages");
        Equal(cleanupMessages[1],OrCADWheelZoom.SignalsEscapeMessage,"directed popup Escape fallback");
        cleanupMessages.Clear(); cleanupDelay=0;
        cleanupResult = OrCADWheelZoom.FinishSignalsPopup(
            delegate {return OrCADWheelZoom.SignalsCleanupProbe.Safe;},
            delegate(uint msg) {cleanupMessages.Add(msg);}, delegate(int ms) {cleanupDelay+=ms;});
        Equal(cleanupResult,OrCADWheelZoom.SignalsCleanupResult.StillOpen,"unresponsive popup is not falsely confirmed closed");
        Equal(cleanupMessages.Count,2,"stubborn popup is not spammed/reinvoked");
        Equal(cleanupDelay,60,"cleanup wait shortened from 100ms to 60ms");
        cleanupMessages.Clear(); cleanupDelay=0; popupVisible=true;
        gesture = new OrCADWheelZoom.SignalsGestureState(); checkpoint=gesture.Generation;
        cleanupResult = OrCADWheelZoom.FinishSignalsPopup(
            delegate {return !popupVisible ? OrCADWheelZoom.SignalsCleanupProbe.Gone : gesture.Unchanged(checkpoint)
                ? OrCADWheelZoom.SignalsCleanupProbe.Safe : OrCADWheelZoom.SignalsCleanupProbe.Unsafe;},
            delegate(uint msg) {cleanupMessages.Add(msg); if(msg==OrCADWheelZoom.SignalsEscapeMessage) popupVisible=false;},
            delegate(int ms) {cleanupDelay+=ms; gesture.Observe(false,0x0200,UIntPtr.Zero);});
        Equal(cleanupResult,OrCADWheelZoom.SignalsCleanupResult.Closed,"hover throughout cleanup still dismisses MFC menu");
        Equal(cleanupDelay,40,"Escape fallback observed after 30+10ms, no grace");
        Equal(cleanupMessages.Count,2,"hover neither duplicates Signals nor prevents fallback");
        cleanupMessages.Clear(); cleanupDelay=0;
        gesture = new OrCADWheelZoom.SignalsGestureState(); checkpoint=gesture.Generation;
        cleanupResult = OrCADWheelZoom.FinishSignalsPopup(
            delegate {return gesture.Unchanged(checkpoint) ? OrCADWheelZoom.SignalsCleanupProbe.Safe : OrCADWheelZoom.SignalsCleanupProbe.Unsafe;},
            delegate(uint msg) {cleanupMessages.Add(msg);}, delegate(int ms) {
                cleanupDelay+=ms; gesture.Observe(false,0x0201,UIntPtr.Zero); gesture.Observe(false,0x0202,UIntPtr.Zero);
            });
        Equal(cleanupResult,OrCADWheelZoom.SignalsCleanupResult.Skipped,"completed fast click after cancel protects user's gesture");
        Equal(cleanupMessages.Count,1,"completed fast click prevents additional Escape");
        cleanupMessages.Clear(); cleanupDelay=0;
        cleanupResult = OrCADWheelZoom.FinishSignalsPopup(
            delegate {return cleanupDelay==0 ? OrCADWheelZoom.SignalsCleanupProbe.Safe : OrCADWheelZoom.SignalsCleanupProbe.Unsafe;},
            delegate(uint msg) {cleanupMessages.Add(msg);}, delegate(int ms) {cleanupDelay+=ms;});
        Equal(cleanupResult,OrCADWheelZoom.SignalsCleanupResult.Skipped,"new interaction after cancel stops cleanup");
        Equal(cleanupMessages.Count,1,"new interaction receives no additional Escape");
        cleanupMessages.Clear(); cleanupDelay=0;
        cleanupResult = OrCADWheelZoom.FinishSignalsPopup(
            delegate {return cleanupMessages.Count==0 ? OrCADWheelZoom.SignalsCleanupProbe.Safe : OrCADWheelZoom.SignalsCleanupProbe.Unsafe;},
            delegate(uint msg) {cleanupMessages.Add(msg);}, delegate(int ms) {cleanupDelay+=ms;});
        Equal(cleanupResult,OrCADWheelZoom.SignalsCleanupResult.Skipped,"context change after cancel prevents fallback");
        Equal(cleanupMessages.Count,1,"context change never sends Escape later");
        cleanupMessages.Clear();
        cleanupResult = OrCADWheelZoom.FinishSignalsPopup(
            delegate {return OrCADWheelZoom.SignalsCleanupProbe.Unsafe;},
            delegate(uint msg) {cleanupMessages.Add(msg);}, delegate(int ms) {});
        Equal(cleanupResult,OrCADWheelZoom.SignalsCleanupResult.Skipped,"unsafe target skipped immediately");
        Equal(cleanupMessages.Count,0,"unsafe popup never receives input");
        cleanupDelay=0; int cleanupProbes=0;
        cleanupResult = OrCADWheelZoom.FinishSignalsPopup(
            delegate {return ++cleanupProbes==1 ? OrCADWheelZoom.SignalsCleanupProbe.Safe : OrCADWheelZoom.SignalsCleanupProbe.Unsafe;},
            delegate(uint msg) {cleanupMessages.Add(msg);}, delegate(int ms) {cleanupDelay+=ms;});
        Equal(cleanupMessages.Count,0,"new input between initial probe and immediate cancel still prevents dismissal");
        Equal(cleanupResult,OrCADWheelZoom.SignalsCleanupResult.Skipped,"zero grace does not bypass final recheck");
        cleanupMessages.Clear(); cleanupDelay=0; popupVisible=true;
        gesture = new OrCADWheelZoom.SignalsGestureState();
        gesture.SeedHeldKeys(delegate(int key) {return key==0x11 || key==0x71;}); checkpoint=gesture.Generation;
        bool shortcutReleased=false;
        cleanupResult = OrCADWheelZoom.FinishSignalsPopup(
            delegate {return !popupVisible ? OrCADWheelZoom.SignalsCleanupProbe.Gone : gesture.Unchanged(checkpoint)
                ? OrCADWheelZoom.SignalsCleanupProbe.Safe : OrCADWheelZoom.SignalsCleanupProbe.Unsafe;},
            delegate(uint msg) {cleanupMessages.Add(msg); if(msg==OrCADWheelZoom.SignalsEscapeMessage) popupVisible=false;},
            delegate(int ms) {cleanupDelay+=ms;
                if (!shortcutReleased) {gesture.ObserveKeyboard(0x0101,0x11); gesture.ObserveKeyboard(0x0101,0x71); shortcutReleased=true;}
                gesture.Observe(false,0x0200,UIntPtr.Zero);});
        Equal(cleanupResult,OrCADWheelZoom.SignalsCleanupResult.Closed,"releasing Ctrl+F2 during hover does not cancel menu dismissal");
        Equal(cleanupMessages.Count,2,"Ctrl+F2 release permits only bounded popup messages");
        string resultTest = Path.Combine(Path.GetTempPath(), "OrCADSignalsAck-" + Guid.NewGuid().ToString("N") + ".result");
        try {
            OrCADWheelZoom.WriteSignalsResult(resultTest,"signals-invoked");
            Equal(File.ReadAllText(resultTest),"signals-invoked","complete UTF-8 acknowledgement");
            Equal(File.Exists(resultTest+".writing"),false,"staging file not published as partial acknowledgement");
            bool overwriteRejected = false;
            try {OrCADWheelZoom.WriteSignalsResult(resultTest,"error");} catch (IOException) {overwriteRejected=true;}
            Equal(overwriteRejected,true,"result acknowledgement not overwritten");
            Equal(File.ReadAllText(resultTest),"signals-invoked","first acknowledgement retained");
            File.Delete(resultTest);
            File.WriteAllText(resultTest+".writing","other request");
            bool collisionRejected = false;
            try {OrCADWheelZoom.WriteSignalsResult(resultTest,"error");} catch (IOException) {collisionRejected=true;}
            Equal(collisionRejected,true,"pre-existing staging file rejected");
            Equal(File.ReadAllText(resultTest+".writing"),"other request","unowned staging file preserved");
        } finally {File.Delete(resultTest); File.Delete(resultTest+".writing");}
        Console.WriteLine("PASS: " + checks + " native policy/packing/ABI checks (" + (IntPtr.Size*8) + "-bit); no UI actions.");
        return 0;
    }
}
