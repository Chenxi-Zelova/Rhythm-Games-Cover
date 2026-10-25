Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$nativeCode = @'
using System;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Xml.Serialization;

public sealed class OverlayPresetPaneRecord
{
    public int X;
    public int Y;
    public int Width;
    public int Height;
    public bool LineVisible;
    public bool LineVertical;
    public float LineRatio;

    public OverlayPresetPaneRecord() { }

    public OverlayPresetPaneRecord(OverlayPaneSettings pane)
    {
        X = pane.Bounds.X;
        Y = pane.Bounds.Y;
        Width = pane.Bounds.Width;
        Height = pane.Bounds.Height;
        LineVisible = pane.LineVisible;
        LineVertical = pane.LineVertical;
        LineRatio = pane.LineRatio;
    }
}

public sealed class OverlayPresetLayoutRecord
{
    public int Mode;
    public int X;
    public int Y;
    public int Width;
    public int Height;
    public int Gap;
    public OverlayPresetPaneRecord FirstPane;
    public OverlayPresetPaneRecord SecondPane;

    public OverlayPresetLayoutRecord()
    {
        FirstPane = new OverlayPresetPaneRecord();
        SecondPane = new OverlayPresetPaneRecord();
    }

    public OverlayPresetLayoutRecord(int mode, OverlayLayoutSettings layout)
    {
        Mode = mode;
        X = layout.Bounds.X;
        Y = layout.Bounds.Y;
        Width = layout.Bounds.Width;
        Height = layout.Bounds.Height;
        Gap = layout.Gap;
        FirstPane = new OverlayPresetPaneRecord(layout.FirstPane);
        SecondPane = new OverlayPresetPaneRecord(layout.SecondPane);
    }
}

public sealed class OverlayPresetFile
{
    public int Version = 1;
    public int ActiveMode;
    public OverlayPresetLayoutRecord[] Layouts = new OverlayPresetLayoutRecord[3];
}

public sealed class OverlayPaneSettings
{
    public Rectangle Bounds;
    public bool LineVisible = true;
    public bool LineVertical;
    public float LineRatio = 0.5f;

    public OverlayPaneSettings(Rectangle bounds)
    {
        Bounds = bounds;
    }
}

public sealed class OverlayLayoutSettings
{
    private const int PaneMoveMargin = 120;
    public Rectangle Bounds;
    public int Gap;
    public OverlayPaneSettings FirstPane;
    public OverlayPaneSettings SecondPane;

    public OverlayLayoutSettings(Rectangle bounds, int mode, int gap)
    {
        if (mode == 1) bounds = new Rectangle(bounds.X, bounds.Y - PaneMoveMargin, bounds.Width, bounds.Height + 2 * PaneMoveMargin);
        else if (mode == 2) bounds = new Rectangle(bounds.X - PaneMoveMargin, bounds.Y, bounds.Width + 2 * PaneMoveMargin, bounds.Height);
        Bounds = bounds;
        Gap = gap;
        FirstPane = new OverlayPaneSettings(bounds);
        SecondPane = new OverlayPaneSettings(bounds);

        if (mode == 1)
        {
            int usableHeight = bounds.Height - 2 * PaneMoveMargin;
            int actualGap = Math.Max(0, Math.Min(gap, usableHeight - 80));
            int firstHeight = (usableHeight - actualGap) / 2;
            int paneWidth = Math.Max(40, bounds.Width - 2 * Math.Min(PaneMoveMargin, (bounds.Width - 40) / 2));
            int paneX = bounds.X + (bounds.Width - paneWidth) / 2;
            int firstY = bounds.Y + PaneMoveMargin;
            FirstPane.Bounds = new Rectangle(paneX, firstY, paneWidth, firstHeight);
            SecondPane.Bounds = new Rectangle(paneX, firstY + firstHeight + actualGap,
                paneWidth, usableHeight - firstHeight - actualGap);
        }
        else if (mode == 2)
        {
            int usableWidth = bounds.Width - 2 * PaneMoveMargin;
            int actualGap = Math.Max(0, Math.Min(gap, usableWidth - 80));
            int firstWidth = (usableWidth - actualGap) / 2;
            int paneHeight = Math.Max(40, bounds.Height - 2 * Math.Min(PaneMoveMargin, (bounds.Height - 40) / 2));
            int paneY = bounds.Y + (bounds.Height - paneHeight) / 2;
            int firstX = bounds.X + PaneMoveMargin;
            FirstPane.Bounds = new Rectangle(firstX, paneY, firstWidth, paneHeight);
            SecondPane.Bounds = new Rectangle(firstX + firstWidth + actualGap, paneY,
                usableWidth - firstWidth - actualGap, paneHeight);
        }
    }
}

public class OverlayPane : Form
{
    private const int WsExTransparent = 0x00000020;
    private const int WsExLayered = 0x00080000;
    private const int WsExNoActivate = 0x08000000;
    private static readonly IntPtr HwndTopmost = new IntPtr(-1);
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpShowWindow = 0x0040;
    private bool lineVisible = true;
    private bool lineVertical;
    private float lineRatio = 0.5f;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(IntPtr hWnd, IntPtr insertAfter, int x, int y, int cx, int cy, uint flags);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetLayeredWindowAttributes(IntPtr hWnd, uint colorKey, byte alpha, uint flags);

    public OverlayPane(bool showInTaskbar)
    {
        FormBorderStyle = FormBorderStyle.None;
        BackColor = Color.Black;
        ShowInTaskbar = showInTaskbar;
        TopMost = true;
        StartPosition = FormStartPosition.Manual;
    }

    public bool LineVisible
    {
        get { return lineVisible; }
        set { lineVisible = value; Invalidate(); }
    }

    public bool LineVertical
    {
        get { return lineVertical; }
        set { lineVertical = value; Invalidate(); }
    }

    public float LineRatio
    {
        get { return lineRatio; }
        set { lineRatio = Math.Max(0f, Math.Min(1f, value)); Invalidate(); }
    }
    private string promptText = String.Empty;
    private string promptDetails = String.Empty;

    public string PromptText
    {
        get { return promptText; }
        set { promptText = value ?? String.Empty; Invalidate(); }
    }

    public string PromptDetails
    {
        get { return promptDetails; }
        set { promptDetails = value ?? String.Empty; Invalidate(); }
    }

    public void ToggleLineVisibility()
    {
        LineVisible = !LineVisible;
    }

    public void ToggleLineOrientation()
    {
        lineVertical = !lineVertical;
        lineRatio = 0.5f;
        Invalidate();
    }

    public void MoveLine(int delta, bool horizontalAxis)
    {
        if (lineVertical != horizontalAxis) return;
        int extent = lineVertical ? ClientSize.Width : ClientSize.Height;
        if (extent <= 1) return;
        int position = (int)Math.Round(lineRatio * (extent - 1));
        position = Math.Max(0, Math.Min(position + delta, extent - 1));
        lineRatio = (float)position / (extent - 1);
        Invalidate();
    }

    public void PositionWithoutActivation(Rectangle bounds)
    {
        if (!IsHandleCreated || !Visible)
        {
            Bounds = bounds;
            return;
        }
        SetWindowPos(Handle, HwndTopmost, bounds.X, bounds.Y, bounds.Width, bounds.Height, SwpNoActivate | SwpShowWindow);
    }

    protected override bool ShowWithoutActivation
    {
        get { return true; }
    }

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams parameters = base.CreateParams;
            parameters.ExStyle |= WsExTransparent | WsExLayered | WsExNoActivate;
            return parameters;
        }
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        if (ClientSize.Width <= 0 || ClientSize.Height <= 0) return;

        if (lineVisible)
        {
            using (Pen linePen = new Pen(Color.White, 2))
            {
                if (lineVertical)
                {
                    int x = (int)Math.Round(lineRatio * (ClientSize.Width - 1));
                    e.Graphics.DrawLine(linePen, x, 0, x, ClientSize.Height);
                }
                else
                {
                    int y = (int)Math.Round(lineRatio * (ClientSize.Height - 1));
                    e.Graphics.DrawLine(linePen, 0, y, ClientSize.Width, y);
                }
            }
        }

        if (!String.IsNullOrEmpty(promptText))
        {
            using (Font titleFont = new Font("Microsoft YaHei UI", 10, FontStyle.Bold))
            using (Font detailFont = new Font("Microsoft YaHei UI", 9, FontStyle.Regular))
            using (Brush textBrush = new SolidBrush(Color.White))
            using (StringFormat format = new StringFormat())
            {
                format.Alignment = StringAlignment.Center;
                format.LineAlignment = StringAlignment.Center;
                e.Graphics.DrawString(promptText, titleFont, textBrush,
                    new RectangleF(12, 8, ClientSize.Width - 24, 30), format);
                if (!String.IsNullOrEmpty(promptDetails))
                    e.Graphics.DrawString(promptDetails, detailFont, textBrush,
                        new RectangleF(12, 38, ClientSize.Width - 24, 24), format);
            }
        }
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        SetLayeredWindowAttributes(Handle, 0, 255, 0x00000002);
        SetWindowPos(Handle, HwndTopmost, Left, Top, Width, Height, SwpNoActivate | SwpShowWindow);
    }
}

public sealed class BlackOverlay : OverlayPane
{
    private const int WmHotkey = 0x0312;
    private const int WhKeyboardLl = 13;
    private const int HcAction = 0;
    private const int WmKeyDown = 0x0100;
    private const int WmKeyUp = 0x0101;
    private const int WmSysKeyDown = 0x0104;
    private const int WmSysKeyUp = 0x0105;
    private const uint ModAlt = 0x0001;
    private const uint ModControl = 0x0002;
    private const uint ModShift = 0x0004;
    private const uint ModNoRepeat = 0x4000;
    private const int SizeStep = 40;
    private const int PaneMoveMargin = 120;
    private readonly OverlayPane secondPane;
    private readonly OverlayPane resetPromptPane;
    private readonly OverlayLayoutSettings[] layouts = new OverlayLayoutSettings[3];
    private readonly string presetDirectory;
    private Rectangle layoutBounds;
    private Rectangle firstPaneBounds;
    private Rectangle secondPaneBounds;
    private int splitMode;
    private int gap = 40;
    private bool controlDown;
    private bool shiftDown;
    private bool altDown;
    private bool leftShiftDown;
    private bool rightShiftDown;
    private bool leftAltDown;
    private bool rightAltDown;
    private bool spaceKeyHandled;
    private bool resetPending;
    private bool resetEscapeHandled;
    private int overwritePendingSlot = -1;
    private readonly Timer statusTimer;
    private readonly bool[] digitDown = new bool[3];
    private readonly bool[] digitAlt = new bool[3];
    private readonly bool[] digitControl = new bool[3];
    private readonly bool[] digitShift = new bool[3];
    private readonly bool[] digitControlAlt = new bool[3];
    private readonly bool[] digitAltChordUsed = new bool[3];
    private readonly bool[] digitControlChordUsed = new bool[3];
    private readonly bool[] digitControlAltChordUsed = new bool[3];
    private readonly bool[] suppressDigitKey = new bool[3];
    private readonly bool[] presetDigitHandled = new bool[10];
    private readonly bool[] suppressArrowKeyUp = new bool[4];
    private readonly LowLevelKeyboardProc keyboardProc;
    private IntPtr keyboardHook;

    private delegate IntPtr LowLevelKeyboardProc(int code, IntPtr message, IntPtr data);

    [StructLayout(LayoutKind.Sequential)]
    private struct KeyboardHookData
    {
        public uint VirtualKey;
        public uint ScanCode;
        public uint Flags;
        public uint Time;
        public UIntPtr ExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint key);

    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int hookType, LowLevelKeyboardProc callback, IntPtr module, uint threadId);

    [DllImport("user32.dll")]
    private static extern bool UnhookWindowsHookEx(IntPtr hook);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string moduleName);

    public BlackOverlay(string presetDirectory) : base(true)
    {
        this.presetDirectory = Path.GetFullPath(presetDirectory);
        Rectangle screen = Screen.PrimaryScreen.Bounds;
        int width = Math.Min(480, screen.Width);
        int height = Math.Min(300, screen.Height);
        layoutBounds = new Rectangle(screen.Left + (screen.Width - width) / 2, screen.Top + (screen.Height - height) / 2, width, height);
        layouts[0] = new OverlayLayoutSettings(layoutBounds, 0, gap);
        layouts[1] = new OverlayLayoutSettings(layoutBounds, 1, gap);
        layouts[2] = new OverlayLayoutSettings(layoutBounds, 2, gap);
        secondPane = new OverlayPane(false);
        secondPane.Bounds = layoutBounds;
        resetPromptPane = new OverlayPane(false);
        resetPromptPane.LineVisible = false;
        statusTimer = new Timer();
        statusTimer.Interval = 1800;
        statusTimer.Tick += delegate
        {
            statusTimer.Stop();
            if (!resetPending && overwritePendingSlot < 0)
            {
                resetPromptPane.PromptText = String.Empty;
                resetPromptPane.PromptDetails = String.Empty;
                resetPromptPane.Hide();
            }
        };
        LoadLayoutState(0);
        Bounds = firstPaneBounds;
        keyboardProc = KeyboardHookCallback;
    }

    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e);
        RegisterHotkeys();
        keyboardHook = SetWindowsHookEx(WhKeyboardLl, keyboardProc, GetModuleHandle(null), 0);
        ApplyLayout();
    }

    private void RegisterHotkeys()
    {
        RegisterActiveHotkeys();
        RegisterHotKey(Handle, 13, ModShift, 0x20);
    }

    private void RegisterActiveHotkeys()
    {
        RegisterHotKey(Handle, 1, ModControl, 0x25);
        RegisterHotKey(Handle, 2, ModControl, 0x27);
        RegisterHotKey(Handle, 3, ModControl, 0x26);
        RegisterHotKey(Handle, 4, ModControl, 0x28);
        RegisterHotKey(Handle, 5, ModShift, 0x25);
        RegisterHotKey(Handle, 6, ModShift, 0x27);
        RegisterHotKey(Handle, 7, ModShift, 0x26);
        RegisterHotKey(Handle, 8, ModShift, 0x28);
        RegisterHotKey(Handle, 9, ModAlt, 0x25);
        RegisterHotKey(Handle, 10, ModAlt, 0x27);
        RegisterHotKey(Handle, 11, ModAlt, 0x26);
        RegisterHotKey(Handle, 12, ModAlt, 0x28);
        RegisterHotKey(Handle, 14, ModControl | ModNoRepeat, 0x74);
    }

    private void UnregisterActiveHotkeys()
    {
        for (int id = 1; id <= 12; id++) UnregisterHotKey(Handle, id);
        UnregisterHotKey(Handle, 14);
    }

    protected override void WndProc(ref Message message)
    {
        if (message.Msg == WmHotkey)
        {
            HandleHotkey(message.WParam.ToInt32());
            return;
        }
        base.WndProc(ref message);
    }

    private void HandleHotkey(int id)
    {
        if (id == 13)
        {
            ToggleOverlayVisibility();
            return;
        }

        if (id == 14)
        {
            HandleResetHotkey();
            return;
        }

        if (id >= 1 && id <= 4)
        {
            ResizeLayout(id);
            return;
        }

        if (id >= 5 && id <= 8)
        {
            MoveLayout(id);
            return;
        }

        if (id >= 9 && id <= 12)
        {
            int delta = (id == 9 || id == 11) ? -SizeStep : SizeStep;
            bool horizontalAxis = id == 9 || id == 10;
            MoveAllLines(delta, horizontalAxis);
            return;
        }

    }

    private void ResizeLayout(int id)
    {
        int width = layoutBounds.Width;
        int height = layoutBounds.Height;
        if (id == 1) width -= SizeStep;
        if (id == 2) width += SizeStep;
        if (id == 3) height += SizeStep;
        if (id == 4) height -= SizeStep;

        Rectangle screen = Screen.FromHandle(Handle).Bounds;
        int minimumWidth = splitMode == 2 ? 2 * PaneMoveMargin + gap + 80 : 120;
        int minimumHeight = splitMode == 1 ? 2 * PaneMoveMargin + gap + 80 : 80;
        width = Math.Max(minimumWidth, Math.Min(width, Math.Max(minimumWidth, screen.Width)));
        height = Math.Max(minimumHeight, Math.Min(height, Math.Max(minimumHeight, screen.Height)));
        layoutBounds = new Rectangle(layoutBounds.Left + (layoutBounds.Width - width) / 2,
            layoutBounds.Top + (layoutBounds.Height - height) / 2, width, height);
        if (splitMode == 0) firstPaneBounds = layoutBounds;
        else CalculateSplitBounds();
        ApplyLayout();
    }

    private void MoveLayout(int id)
    {
        int x = layoutBounds.X;
        int y = layoutBounds.Y;
        if (id == 5) x -= SizeStep;
        if (id == 6) x += SizeStep;
        if (id == 7) y -= SizeStep;
        if (id == 8) y += SizeStep;
        int deltaX = x - layoutBounds.X;
        int deltaY = y - layoutBounds.Y;
        layoutBounds.Location = new Point(x, y);
        if (splitMode == 0) firstPaneBounds = layoutBounds;
        else
        {
            firstPaneBounds.Offset(deltaX, deltaY);
            secondPaneBounds.Offset(deltaX, deltaY);
        }
        ApplyLayout();
    }

    private void ChangeLayout(int mode)
    {
        if (mode < 0 || mode > 2 || mode == splitMode) return;
        SaveLayoutState();
        LoadLayoutState(mode);
        ApplyLayout();
    }

    private void SaveLayoutState()
    {
        OverlayLayoutSettings state = layouts[splitMode];
        state.Bounds = layoutBounds;
        state.Gap = gap;
        state.FirstPane.Bounds = firstPaneBounds;
        state.SecondPane.Bounds = secondPaneBounds;
        state.FirstPane.LineVisible = LineVisible;
        state.FirstPane.LineVertical = LineVertical;
        state.FirstPane.LineRatio = LineRatio;
        state.SecondPane.LineVisible = secondPane.LineVisible;
        state.SecondPane.LineVertical = secondPane.LineVertical;
        state.SecondPane.LineRatio = secondPane.LineRatio;
    }

    private void LoadLayoutState(int mode)
    {
        splitMode = mode;
        OverlayLayoutSettings state = layouts[mode];
        layoutBounds = state.Bounds;
        gap = state.Gap;
        firstPaneBounds = state.FirstPane.Bounds;
        secondPaneBounds = state.SecondPane.Bounds;
        LineVisible = state.FirstPane.LineVisible;
        LineVertical = state.FirstPane.LineVertical;
        LineRatio = state.FirstPane.LineRatio;
        secondPane.LineVisible = state.SecondPane.LineVisible;
        secondPane.LineVertical = state.SecondPane.LineVertical;
        secondPane.LineRatio = state.SecondPane.LineRatio;
    }

    private void CalculateSplitBounds()
    {
        int extent = splitMode == 1 ? layoutBounds.Height : layoutBounds.Width;
        int usableExtent = extent - 2 * PaneMoveMargin;
        gap = Math.Max(0, Math.Min(gap, usableExtent - 80));
        if (splitMode == 1)
        {
            int paneContentHeight = layoutBounds.Height - 2 * PaneMoveMargin;
            int firstHeight = (paneContentHeight - gap) / 2;
            int paneWidth = Math.Max(40, layoutBounds.Width - 2 * Math.Min(PaneMoveMargin, (layoutBounds.Width - 40) / 2));
            int paneX = layoutBounds.X + (layoutBounds.Width - paneWidth) / 2;
            int firstY = layoutBounds.Y + PaneMoveMargin;
            firstPaneBounds = new Rectangle(paneX, firstY, paneWidth, firstHeight);
            secondPaneBounds = new Rectangle(paneX, firstY + firstHeight + gap,
                paneWidth, paneContentHeight - firstHeight - gap);
        }
        else
        {
            int paneContentWidth = layoutBounds.Width - 2 * PaneMoveMargin;
            int firstWidth = (paneContentWidth - gap) / 2;
            int paneHeight = Math.Max(40, layoutBounds.Height - 2 * Math.Min(PaneMoveMargin, (layoutBounds.Height - 40) / 2));
            int paneY = layoutBounds.Y + (layoutBounds.Height - paneHeight) / 2;
            int firstX = layoutBounds.X + PaneMoveMargin;
            firstPaneBounds = new Rectangle(firstX, paneY, firstWidth, paneHeight);
            secondPaneBounds = new Rectangle(firstX + firstWidth + gap, paneY,
                paneContentWidth - firstWidth - gap, paneHeight);
        }
    }

    private void ApplyLayout()
    {
        if (splitMode == 0)
        {
            secondPane.Hide();
            PositionWithoutActivation(layoutBounds);
            return;
        }

        if (!Visible)
        {
            Bounds = firstPaneBounds;
            secondPane.Bounds = secondPaneBounds;
            secondPane.Hide();
            return;
        }

        PositionWithoutActivation(firstPaneBounds);
        secondPane.PositionWithoutActivation(secondPaneBounds);
        if (!secondPane.Visible) secondPane.Show();
        secondPane.PositionWithoutActivation(secondPaneBounds);
    }

    private OverlayPane GetPane(int pane)
    {
        return pane == 0 ? (OverlayPane)this : secondPane;
    }

    private Rectangle GetPaneBounds(int pane)
    {
        return pane == 0 ? firstPaneBounds : secondPaneBounds;
    }

    private void SetPaneBounds(int pane, Rectangle bounds)
    {
        if (bounds.Width < 40 || bounds.Height < 40) return;
        Rectangle other = GetPaneBounds(1 - pane);
        if (bounds.IntersectsWith(other)) return;

        if (pane == 0) firstPaneBounds = bounds;
        else secondPaneBounds = bounds;
        ApplyLayout();
    }

    private void MovePane(int pane, int key)
    {
        Rectangle bounds = GetPaneBounds(pane);
        int x = bounds.X;
        int y = bounds.Y;
        if (key == 0x25) x -= SizeStep;
        if (key == 0x27) x += SizeStep;
        if (key == 0x26) y -= SizeStep;
        if (key == 0x28) y += SizeStep;
        SetPaneBounds(pane, new Rectangle(x, y, bounds.Width, bounds.Height));
    }

    private void ResizePane(int pane, int key)
    {
        Rectangle bounds = GetPaneBounds(pane);
        int width = bounds.Width;
        int height = bounds.Height;
        int x = bounds.X;
        int y = bounds.Y;

        if (key == 0x25)
        {
            width -= SizeStep;
            if (splitMode == 2 && pane == 1) x += SizeStep;
        }
        if (key == 0x27)
        {
            width += SizeStep;
            if (splitMode == 2 && pane == 1) x -= SizeStep;
        }
        if (key == 0x26)
        {
            height += SizeStep;
            if (splitMode == 1 && pane == 1) y -= SizeStep;
        }
        if (key == 0x28)
        {
            height -= SizeStep;
            if (splitMode == 1 && pane == 1) y += SizeStep;
        }
        SetPaneBounds(pane, new Rectangle(x, y, width, height));
    }

    private void MovePaneLine(int pane, int key)
    {
        bool horizontalAxis = key == 0x25 || key == 0x27;
        int delta = key == 0x25 || key == 0x26 ? -SizeStep : SizeStep;
        GetPane(pane).MoveLine(delta, horizontalAxis);
    }

    private void TogglePaneLine(int pane)
    {
        GetPane(pane).ToggleLineVisibility();
    }

    private bool ProcessPaneArrow(int key, bool keyDown)
    {
        int arrowIndex = key == 0x25 ? 0 : key == 0x27 ? 1 : key == 0x26 ? 2 : key == 0x28 ? 3 : -1;
        if (arrowIndex < 0) return false;
        if (!keyDown)
        {
            bool suppress = suppressArrowKeyUp[arrowIndex];
            suppressArrowKeyUp[arrowIndex] = false;
            return suppress;
        }

        if (splitMode == 0) return false;
        for (int pane = 0; pane < 2; pane++)
        {
            if (digitDown[pane] && digitControl[pane] && controlDown && !altDown && !shiftDown)
            {
                ResizePane(pane, key);
                suppressArrowKeyUp[arrowIndex] = true;
                return true;
            }
            if (digitDown[pane] && digitShift[pane] && shiftDown && !controlDown && !altDown)
            {
                MovePane(pane, key);
                suppressArrowKeyUp[arrowIndex] = true;
                return true;
            }
            if (digitDown[pane] && digitAlt[pane] && altDown && !controlDown && !shiftDown)
            {
                MovePaneLine(pane, key);
                suppressArrowKeyUp[arrowIndex] = true;
                return true;
            }
        }
        return false;
    }

    private void ToggleOverlayVisibility()
    {
        if (Visible)
        {
            CancelResetPrompt();
            CancelOverwritePrompt();
            secondPane.Hide();
            Hide();
            UnregisterActiveHotkeys();
        }
        else
        {
            Show();
            RegisterActiveHotkeys();
            ApplyLayout();
        }
    }

    private void HandleResetHotkey()
    {
        CancelOverwritePrompt();
        if (resetPending)
        {
            ResetCurrentLayoutState();
            return;
        }

        resetPending = true;
        ShowPrompt("\u786E\u8BA4\u91CD\u7F6E\u5F53\u524D\u5E03\u5C40\uFF1F",
            "\u518D\u6B21\u6309 Ctrl+F5 \u786E\u8BA4\uFF0CEsc \u53D6\u6D88");
    }

    private void CancelResetPrompt()
    {
        resetPending = false;
        statusTimer.Stop();
        resetPromptPane.PromptText = String.Empty;
        resetPromptPane.PromptDetails = String.Empty;
        resetPromptPane.Hide();
    }

    private void ShowPrompt(string title, string details)
    {
        resetPromptPane.PromptText = title;
        resetPromptPane.PromptDetails = details;
        Rectangle screen = Screen.FromHandle(Handle).Bounds;
        int width = Math.Min(screen.Width, Math.Max(320, Math.Min(560, layoutBounds.Width)));
        int height = Math.Min(76, screen.Height);
        Rectangle promptBounds = new Rectangle(screen.Left + (screen.Width - width) / 2,
            screen.Top + (screen.Height - height) / 3, width, height);
        resetPromptPane.PositionWithoutActivation(promptBounds);
        if (!resetPromptPane.Visible) resetPromptPane.Show();
        resetPromptPane.PositionWithoutActivation(promptBounds);
    }

    private void ShowStatus(string message)
    {
        resetPending = false;
        overwritePendingSlot = -1;
        statusTimer.Stop();
        ShowPrompt(message, String.Empty);
        statusTimer.Start();
    }

    private void CancelOverwritePrompt()
    {
        if (overwritePendingSlot < 0) return;
        overwritePendingSlot = -1;
        if (!resetPending)
        {
            statusTimer.Stop();
            resetPromptPane.PromptText = String.Empty;
            resetPromptPane.PromptDetails = String.Empty;
            resetPromptPane.Hide();
        }
    }

    private void ResetCurrentLayoutState()
    {
        SaveLayoutState();
        OverlayLayoutSettings previous = layouts[splitMode];
        Rectangle screen = Screen.FromHandle(Handle).Bounds;
        int width = Math.Min(480, screen.Width);
        int height = Math.Min(300, screen.Height);
        Rectangle defaultBounds = new Rectangle(screen.Left + (screen.Width - width) / 2,
            screen.Top + (screen.Height - height) / 2, width, height);
        OverlayLayoutSettings reset = new OverlayLayoutSettings(defaultBounds, splitMode, 40);
        reset.FirstPane.LineVisible = true;
        reset.FirstPane.LineVertical = previous.FirstPane.LineVertical;
        reset.SecondPane.LineVisible = true;
        reset.SecondPane.LineVertical = previous.SecondPane.LineVertical;
        layouts[splitMode] = reset;
        LoadLayoutState(splitMode);
        CancelResetPrompt();
        ApplyLayout();
    }

    private void ToggleAllLineVisibility()
    {
        bool allVisible = LineVisible && (splitMode == 0 || secondPane.LineVisible);
        bool show = !allVisible;
        LineVisible = show;
        secondPane.LineVisible = show;
    }

    private void ToggleAllLineOrientation()
    {
        ToggleLineOrientation();
        secondPane.ToggleLineOrientation();
    }

    private void TogglePaneLineVisibility(int pane)
    {
        if (pane == 0) ToggleLineVisibility();
        else secondPane.ToggleLineVisibility();
    }

    private void TogglePaneLineOrientation(int pane)
    {
        if (pane == 0) ToggleLineOrientation();
        else secondPane.ToggleLineOrientation();
    }

    private void MoveAllLines(int delta, bool horizontalAxis)
    {
        base.MoveLine(delta, horizontalAxis);
        if (splitMode != 0) secondPane.MoveLine(delta, horizontalAxis);
    }

    private string GetPresetPath(int slot)
    {
        return Path.Combine(presetDirectory, String.Format("preset-{0}.rgc", slot));
    }

    private void RequestSavePreset(int slot)
    {
        if (resetPending) CancelResetPrompt();
        if (overwritePendingSlot >= 0 && overwritePendingSlot != slot) CancelOverwritePrompt();

        if (File.Exists(GetPresetPath(slot)))
        {
            if (overwritePendingSlot == slot)
            {
                overwritePendingSlot = -1;
                ShowStatus(WritePresetFile(slot)
                    ? "\u5DF2\u8986\u76D6\u9884\u8BBE " + slot
                    : "\u4FDD\u5B58\u9884\u8BBE\u5931\u8D25 " + slot);
                return;
            }

            overwritePendingSlot = slot;
            statusTimer.Stop();
            ShowPrompt("\u9884\u8BBE " + slot + " \u5DF2\u5B58\u5728\uFF0C\u662F\u5426\u8986\u76D6\uFF1F",
                "\u518D\u6B21\u6309\u53F3 Alt+" + slot + " \u8986\u76D6\uFF0CEsc \u53D6\u6D88");
            return;
        }

        ShowStatus(WritePresetFile(slot)
            ? "\u5DF2\u4FDD\u5B58\u5230\u9884\u8BBE " + slot
            : "\u4FDD\u5B58\u9884\u8BBE\u5931\u8D25 " + slot);
    }

    private bool WritePresetFile(int slot)
    {
        try
        {
            SaveLayoutState();
            OverlayPresetFile preset = new OverlayPresetFile();
            preset.ActiveMode = splitMode;
            for (int mode = 0; mode < layouts.Length; mode++)
                preset.Layouts[mode] = new OverlayPresetLayoutRecord(mode, layouts[mode]);

            Directory.CreateDirectory(presetDirectory);
            XmlSerializer serializer = new XmlSerializer(typeof(OverlayPresetFile));
            using (FileStream stream = new FileStream(GetPresetPath(slot), FileMode.Create, FileAccess.Write, FileShare.None))
                serializer.Serialize(stream, preset);
            return true;
        }
        catch (Exception)
        {
            return false;
        }
    }

    private bool IsValidPresetLayout(OverlayPresetLayoutRecord record, int mode)
    {
        return record != null && record.Mode == mode && record.Width >= 80 && record.Height >= 80 && record.Gap >= 0 &&
            record.FirstPane != null && record.SecondPane != null &&
            record.FirstPane.Width >= 40 && record.FirstPane.Height >= 40 &&
            record.SecondPane.Width >= 40 && record.SecondPane.Height >= 40 &&
            record.FirstPane.LineRatio >= 0f && record.FirstPane.LineRatio <= 1f &&
            record.SecondPane.LineRatio >= 0f && record.SecondPane.LineRatio <= 1f;
    }

    private void LoadPreset(int slot)
    {
        if (resetPending) CancelResetPrompt();
        CancelOverwritePrompt();
        string path = GetPresetPath(slot);
        if (!File.Exists(path))
        {
            ShowStatus("\u672A\u627E\u5230\u9884\u8BBE " + slot);
            return;
        }

        try
        {
            OverlayPresetFile preset;
            XmlSerializer serializer = new XmlSerializer(typeof(OverlayPresetFile));
            using (FileStream stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
                preset = (OverlayPresetFile)serializer.Deserialize(stream);

            if (preset == null || preset.Version != 1 || preset.ActiveMode < 0 || preset.ActiveMode >= layouts.Length ||
                preset.Layouts == null || preset.Layouts.Length != layouts.Length)
            {
                ShowStatus("\u9884\u8BBE\u6587\u4EF6\u65E0\u6548 " + slot);
                return;
            }

            for (int mode = 0; mode < layouts.Length; mode++)
            {
                OverlayPresetLayoutRecord record = preset.Layouts[mode];
                if (!IsValidPresetLayout(record, mode))
                {
                    ShowStatus("\u9884\u8BBE\u6587\u4EF6\u65E0\u6548 " + slot);
                    return;
                }
            }

            for (int mode = 0; mode < layouts.Length; mode++)
            {
                OverlayPresetLayoutRecord record = preset.Layouts[mode];
                OverlayLayoutSettings state = layouts[mode];
                state.Bounds = new Rectangle(record.X, record.Y, record.Width, record.Height);
                state.Gap = record.Gap;
                state.FirstPane.Bounds = new Rectangle(record.FirstPane.X, record.FirstPane.Y,
                    record.FirstPane.Width, record.FirstPane.Height);
                state.FirstPane.LineVisible = record.FirstPane.LineVisible;
                state.FirstPane.LineVertical = record.FirstPane.LineVertical;
                state.FirstPane.LineRatio = record.FirstPane.LineRatio;
                state.SecondPane.Bounds = new Rectangle(record.SecondPane.X, record.SecondPane.Y,
                    record.SecondPane.Width, record.SecondPane.Height);
                state.SecondPane.LineVisible = record.SecondPane.LineVisible;
                state.SecondPane.LineVertical = record.SecondPane.LineVertical;
                state.SecondPane.LineRatio = record.SecondPane.LineRatio;
            }

            CancelResetPrompt();
            LoadLayoutState(preset.ActiveMode);
            ApplyLayout();
            ShowStatus("\u5DF2\u8BFB\u53D6\u9884\u8BBE " + slot);
        }
        catch (Exception)
        {
            ShowStatus("\u8BFB\u53D6\u9884\u8BBE\u5931\u8D25 " + slot);
        }
    }

    private IntPtr KeyboardHookCallback(int code, IntPtr message, IntPtr data)
    {
        if (!Visible) return CallNextHookEx(keyboardHook, code, message, data);

        if (code == HcAction)
        {
            int messageCode = message.ToInt32();
            bool keyDown = messageCode == WmKeyDown || messageCode == WmSysKeyDown;
            bool keyUp = messageCode == WmKeyUp || messageCode == WmSysKeyUp;
            if (keyDown || keyUp)
            {
                KeyboardHookData keyData = (KeyboardHookData)Marshal.PtrToStructure(data, typeof(KeyboardHookData));
                if (ProcessKeyboardEvent((int)keyData.VirtualKey, keyDown)) return new IntPtr(1);
            }
        }
        return CallNextHookEx(keyboardHook, code, message, data);
    }

    private bool ProcessKeyboardEvent(int key, bool keyDown)
    {
        if (key == 0x11 || key == 0xA2 || key == 0xA3)
        {
            controlDown = keyDown;
            return false;
        }
        if (key == 0x10)
        {
            shiftDown = keyDown;
            return false;
        }
        if (key == 0xA0)
        {
            leftShiftDown = keyDown;
            shiftDown = leftShiftDown || rightShiftDown;
            return false;
        }
        if (key == 0xA1)
        {
            rightShiftDown = keyDown;
            shiftDown = leftShiftDown || rightShiftDown;
            return false;
        }
        if (key == 0x12)
        {
            altDown = keyDown;
            return false;
        }
        if (key == 0xA4)
        {
            leftAltDown = keyDown;
            altDown = leftAltDown || rightAltDown;
            return false;
        }
        if (key == 0xA5)
        {
            rightAltDown = keyDown;
            altDown = leftAltDown || rightAltDown;
            return false;
        }
        if (key == 0x1B)
        {
            if (!keyDown)
            {
                bool suppress = resetEscapeHandled;
                resetEscapeHandled = false;
                return suppress;
            }
            if (resetPending)
            {
                CancelResetPrompt();
                resetEscapeHandled = true;
                return true;
            }
            if (overwritePendingSlot >= 0)
            {
                CancelOverwritePrompt();
                resetEscapeHandled = true;
                return true;
            }
            return false;
        }
        if (key >= 0x60 && key <= 0x69) key -= 0x30;

        if (key >= 0x30 && key <= 0x39)
        {
            int slot = key - 0x30;
            if (!keyDown)
            {
                bool suppress = presetDigitHandled[slot];
                presetDigitHandled[slot] = false;
                if (suppress) return true;
            }
            else if (presetDigitHandled[slot])
            {
                return true;
            }
            else if (rightAltDown && !rightShiftDown)
            {
                RequestSavePreset(slot);
                presetDigitHandled[slot] = true;
                return true;
            }
            else if (rightShiftDown && !rightAltDown)
            {
                LoadPreset(slot);
                presetDigitHandled[slot] = true;
                return true;
            }
        }

        if (key == 0x25 || key == 0x26 || key == 0x27 || key == 0x28)
            return ProcessPaneArrow(key, keyDown);

        if (key == 0x20)
        {
            if (!keyDown)
            {
                bool suppress = spaceKeyHandled;
                spaceKeyHandled = false;
                return suppress;
            }

            if (spaceKeyHandled) return true;
            if (shiftDown || (controlDown && altDown)) return false;

            if (controlDown && !altDown)
            {
                if (digitDown[0] && digitControl[0] && splitMode != 0)
                {
                    TogglePaneLine(0);
                    digitControlChordUsed[0] = true;
                }
                else if (digitDown[1] && digitControl[1] && splitMode != 0)
                {
                    TogglePaneLine(1);
                    digitControlChordUsed[1] = true;
                }
                else if (!digitDown[0] && !digitDown[1] && !digitDown[2])
                {
                    ToggleAllLineVisibility();
                }
                else
                {
                    return false;
                }
                spaceKeyHandled = true;
                return true;
            }

            if (altDown && !controlDown)
            {
                if (digitDown[0] && digitAlt[0] && splitMode != 0)
                {
                    TogglePaneLineOrientation(0);
                    digitAltChordUsed[0] = true;
                }
                else if (digitDown[1] && digitAlt[1] && splitMode != 0)
                {
                    TogglePaneLineOrientation(1);
                    digitAltChordUsed[1] = true;
                }
                else if (!digitDown[0] && !digitDown[1] && !digitDown[2])
                {
                    ToggleAllLineOrientation();
                }
                else
                {
                    return false;
                }
                spaceKeyHandled = true;
                return true;
            }
            return false;
        }

        if (key >= 0x31 && key <= 0x33)
        {
            int index = key - 0x31;
            if (keyDown)
            {
                if (!digitDown[index])
                {
                    digitDown[index] = true;
                    digitAlt[index] = altDown && !controlDown && !shiftDown;
                    digitControl[index] = controlDown && !altDown && !shiftDown;
                    digitShift[index] = shiftDown && !controlDown && !altDown;
                    digitControlAlt[index] = controlDown && altDown && !shiftDown;
                    digitAltChordUsed[index] = false;
                    digitControlChordUsed[index] = false;
                    digitControlAltChordUsed[index] = false;
                    suppressDigitKey[index] = digitAlt[index] || digitControl[index] || digitShift[index] || digitControlAlt[index];
                }
                return suppressDigitKey[index];
            }

            if (!digitDown[index]) return false;
            if (digitControlAlt[index] && !digitControlAltChordUsed[index]) ChangeLayout(index);
            bool suppressKeyUp = suppressDigitKey[index];
            digitDown[index] = false;
            digitAlt[index] = false;
            digitControl[index] = false;
            digitShift[index] = false;
            digitControlAlt[index] = false;
            digitAltChordUsed[index] = false;
            digitControlChordUsed[index] = false;
            digitControlAltChordUsed[index] = false;
            suppressDigitKey[index] = false;
            return suppressKeyUp;
        }

        return false;
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        for (int id = 1; id <= 13; id++) UnregisterHotKey(Handle, id);
        for (int id = 1; id <= 14; id++) UnregisterHotKey(Handle, id);
        statusTimer.Stop();
        statusTimer.Dispose();
        if (keyboardHook != IntPtr.Zero) UnhookWindowsHookEx(keyboardHook);
        secondPane.Close();
        resetPromptPane.Close();
        base.OnFormClosed(e);
    }
}
'@

Add-Type -TypeDefinition $nativeCode -ReferencedAssemblies @(
    [System.Windows.Forms.Form].Assembly.Location,
    [System.Drawing.Color].Assembly.Location,
    [System.Xml.Serialization.XmlSerializer].Assembly.Location
)

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run([BlackOverlay]::new($PSScriptRoot))