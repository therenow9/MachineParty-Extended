<#
.SYNOPSIS
  Prints the first adapter's DXGI outputs as "<index> <left> <top> <right> <bottom> <dpi> <device>", one a
  line, in physical desktop pixels, with the screen's effective DPI (96 is 100%). ffmpeg's ddagrab numbers its output_idx the same way (EnumOutputs on the
  default adapter), and two screens of one size can't be told apart by ddagrab's own log.
#>
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Dxgi {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct OutputDesc {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        public int Left, Top, Right, Bottom;
        public int AttachedToDesktop, Rotation;
        public IntPtr Monitor;
    }
    [ComImport, Guid("ae02eedb-c735-4690-8d52-5a8dc20213aa"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IOutput {
        void SetPrivateData(); void SetPrivateDataInterface(); void GetPrivateData(); void GetParent();
        [PreserveSig] int GetDesc(out OutputDesc desc);
    }
    [ComImport, Guid("2411e7e1-12ac-4ccf-bd14-9798e8534dc0"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAdapter {
        void SetPrivateData(); void SetPrivateDataInterface(); void GetPrivateData(); void GetParent();
        [PreserveSig] int EnumOutputs(uint i, out IOutput output);
    }
    [ComImport, Guid("770aae78-f26f-4dba-a829-253c83d1b387"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IFactory1 {
        void SetPrivateData(); void SetPrivateDataInterface(); void GetPrivateData(); void GetParent();
        [PreserveSig] int EnumAdapters(uint i, out IAdapter adapter);
    }
    [DllImport("dxgi.dll")] static extern int CreateDXGIFactory1(ref Guid riid, out IFactory1 factory);
    // Without per-monitor awareness Windows scales each rectangle by its screen's DPI, so edges don't meet.
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("shcore.dll")] static extern int GetDpiForMonitor(IntPtr monitor, int type, out uint x, out uint y);
    [DllImport("user32.dll")] static extern IntPtr GetThreadDpiAwarenessContext();
    [DllImport("user32.dll")] static extern bool AreDpiAwarenessContextsEqual(IntPtr a, IntPtr b);
    public static string List() {
        SetProcessDpiAwarenessContext(new IntPtr(-4));
        // Unaware, every screen reads the system's DPI and the caller's scale check passes on a stretched screen.
        if (!AreDpiAwarenessContextsEqual(GetThreadDpiAwarenessContext(), new IntPtr(-4)))
            throw new InvalidOperationException("not per-monitor DPI aware: the rectangles and DPIs would be virtualized");
        Guid g = typeof(IFactory1).GUID;
        IFactory1 f; Marshal.ThrowExceptionForHR(CreateDXGIFactory1(ref g, out f));
        IAdapter a; Marshal.ThrowExceptionForHR(f.EnumAdapters(0, out a));
        var sb = new System.Text.StringBuilder();
        for (uint i = 0; ; i++) {
            IOutput o; if (a.EnumOutputs(i, out o) != 0) break;
            OutputDesc d; Marshal.ThrowExceptionForHR(o.GetDesc(out d));
            uint dx, dy; Marshal.ThrowExceptionForHR(GetDpiForMonitor(d.Monitor, 0, out dx, out dy));
            sb.AppendFormat("{0} {1} {2} {3} {4} {5} {6}\n", i, d.Left, d.Top, d.Right, d.Bottom, dx, d.DeviceName);
        }
        return sb.ToString();
    }
}
'@
[Console]::Out.Write([Dxgi]::List())
