// Couti Installer. GPL-3.0-or-later; see COPYING.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

[assembly: AssemblyTitle("Couti Installer")]
[assembly: AssemblyProduct("Couti Installer")]
[assembly: AssemblyCopyright("iXploiD 2026")]

namespace CoutiInstaller
{
    sealed class Disk
    {
        public int Number { get; set; }
        public string Name { get; set; }
        public string UniqueId { get; set; }
        public string Serial { get; set; }
        public long Size { get; set; }
        public string Style { get; set; }
        public string DevicePath { get; set; }
        public override string ToString() { return "Disk " + Number + "  ·  " + Name + "  ·  " + (Size / 1073741824.0).ToString("0.0") + " GB"; }
    }
    sealed class Inspection
    {
        public bool Present { get; set; }
        public bool RequiresFormat { get; set; }
        public string Details { get; set; }
        public string Layout { get; set; }
    }
    sealed class Reply
    {
        public bool Ok { get; set; }
        public string Message { get; set; }
        public Disk[] Disks { get; set; }
        public Inspection Inspection { get; set; }
    }
    sealed class InstallerForm : Form
    {
        readonly ComboBox disks = new ComboBox();
        readonly Button refresh = new Button(), install = new Button(), remove = new Button();
        readonly CheckBox format = new CheckBox();
        readonly Label presence = new Label(), mode = new Label(), status = new Label();
        readonly ProgressBar progress = new ProgressBar();
        readonly TextBox layout = new TextBox();
        readonly string package = AppDomain.CurrentDomain.BaseDirectory;
        readonly string session;
        readonly string backend;
        readonly JavaScriptSerializer json = new JavaScriptSerializer();
        bool busy, suppress;
        int selectionRevision;
        Disk inspectedDisk;
        Inspection inspection;
        string formatIdentity;
        readonly Color ink = Color.FromArgb(26, 37, 49), accent = Color.FromArgb(0, 112, 133);

        public InstallerForm()
        {
            Text = "Couti Installer";
            Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
            Font = new Font("Segoe UI", 10F);
            BackColor = Color.FromArgb(245, 247, 249);
            ForeColor = ink;
            ClientSize = new Size(730, 650);
            MinimumSize = new Size(746, 689);
            StartPosition = FormStartPosition.CenterScreen;
            AutoScaleMode = AutoScaleMode.Dpi;
            session = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "Couti Installer", "Sessions", Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(session);
            backend = Path.Combine(session, "Couti.Storage.ps1");
            using (Stream source = Assembly.GetExecutingAssembly().GetManifestResourceStream("Couti.Storage.ps1"))
            using (FileStream target = File.Create(backend)) source.CopyTo(target);
            BuildLayout();
            Shown += async delegate { await RefreshDisks(); };
            FormClosing += delegate(object sender, FormClosingEventArgs e) {
                if (busy) { e.Cancel = true; MessageBox.Show(this, "Please wait for the current operation to finish.", Text); }
            };
        }

        void BuildLayout()
        {
            var grid = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(26, 20, 26, 14), ColumnCount = 1, RowCount = 10 };
            int[] heights = { 67, 29, 40, 49, 91, 35, 69, 50, 44, 24 };
            for (int index = 0; index < heights.Length; index++)
                grid.RowStyles.Add(index == 4 ? new RowStyle(SizeType.Percent, 100) : new RowStyle(SizeType.Absolute, heights[index]));
            Controls.Add(grid);
            var heading = new Label { Text = "Couti Installer", Font = new Font(Font.FontFamily, 23F, FontStyle.Bold), Dock = DockStyle.Fill, ForeColor = ink };
            grid.Controls.Add(heading, 0, 0);
            grid.Controls.Add(new Label { Text = "Select a drive", Dock = DockStyle.Fill, Font = new Font(Font, FontStyle.Bold) }, 0, 1);
            var picker = new TableLayoutPanel { ColumnCount = 2, Dock = DockStyle.Fill, Margin = Padding.Empty };
            picker.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            picker.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 90));
            disks.DropDownStyle = ComboBoxStyle.DropDownList; disks.Dock = DockStyle.Fill;
            refresh.Text = "Refresh"; refresh.Dock = DockStyle.Fill; refresh.Margin = new Padding(8, 0, 0, 0);
            picker.Controls.Add(disks, 0, 0); picker.Controls.Add(refresh, 1, 0); grid.Controls.Add(picker, 0, 2);
            presence.Text = "Select a drive to check for Couti"; presence.Dock = DockStyle.Fill; presence.Padding = new Padding(0, 12, 0, 0); presence.Font = new Font(Font, FontStyle.Bold);
            grid.Controls.Add(presence, 0, 3);
            layout.ReadOnly = true; layout.Multiline = true; layout.ScrollBars = ScrollBars.Vertical;
            layout.BorderStyle = BorderStyle.None; layout.BackColor = Color.White; layout.Dock = DockStyle.Fill;
            layout.Margin = new Padding(0, 0, 0, 10); layout.TabStop = false; grid.Controls.Add(layout, 0, 4);
            format.Text = "Format drive"; format.AutoSize = true; format.Checked = false; grid.Controls.Add(format, 0, 5);
            mode.Dock = DockStyle.Fill; mode.Text = "Keep existing files and labels. Create a 100 MB FAT32 COUTI boot partition using available space or a supported partition shrink.";
            grid.Controls.Add(mode, 0, 6);
            var actions = new FlowLayoutPanel { Dock = DockStyle.Fill, FlowDirection = FlowDirection.LeftToRight, Margin = Padding.Empty };
            install.Text = "Install"; install.Size = new Size(148, 38); install.BackColor = accent; install.ForeColor = Color.White; install.FlatStyle = FlatStyle.Flat; install.FlatAppearance.BorderSize = 0;
            remove.Text = "Remove"; remove.Size = new Size(148, 38); remove.Margin = new Padding(12, 3, 3, 3);
            actions.Controls.Add(install); actions.Controls.Add(remove); grid.Controls.Add(actions, 0, 7);
            var bottom = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1, RowCount = 2, Margin = Padding.Empty };
            bottom.RowStyles.Add(new RowStyle(SizeType.Absolute, 23)); bottom.RowStyles.Add(new RowStyle(SizeType.Absolute, 9));
            status.Text = "Ready"; status.Dock = DockStyle.Fill; status.AutoEllipsis = true;
            progress.Dock = DockStyle.Fill; progress.Visible = false;
            bottom.Controls.Add(status, 0, 0); bottom.Controls.Add(progress, 0, 1); grid.Controls.Add(bottom, 0, 8);
            grid.Controls.Add(new Label { Text = "iXploiD 2026", TextAlign = ContentAlignment.MiddleRight, Dock = DockStyle.Fill, ForeColor = Color.FromArgb(94, 106, 119) }, 0, 9);
            refresh.Click += async delegate { await RefreshDisks(); };
            disks.SelectedIndexChanged += async delegate { if (!suppress) await InspectSelection(); };
            format.CheckedChanged += delegate { FormatChanged(); };
            install.Click += async delegate { await Perform("Install"); };
            remove.Click += async delegate { await Perform("Remove"); };
            UpdateControls();
        }

        string Identity(Disk disk) { return disk == null ? null : disk.Number + "|" + disk.UniqueId + "|" + disk.Serial + "|" + disk.Size; }
        void UpdateControls()
        {
            bool ready = !busy && inspection != null && Identity(inspectedDisk) == Identity(disks.SelectedItem as Disk);
            disks.Enabled = refresh.Enabled = !busy;
            format.Enabled = ready;
            install.Enabled = ready && (format.Checked || (!inspection.Present && !inspection.RequiresFormat));
            remove.Enabled = ready && inspection.Present && !format.Checked;
            progress.Visible = busy; progress.Style = ProgressBarStyle.Marquee;
        }
        void ResetFormat()
        {
            suppress = true; format.Checked = false; suppress = false; formatIdentity = null;
            mode.ForeColor = ink;
            mode.Text = "Keep existing files and labels. Create a 100 MB FAT32 COUTI boot partition using available space or a supported partition shrink.";
        }
        void FormatChanged()
        {
            if (suppress) return;
            Disk disk = disks.SelectedItem as Disk;
            if (format.Checked)
            {
                if (disk == null || !ConfirmFormat(disk)) { ResetFormat(); UpdateControls(); return; }
                formatIdentity = Identity(disk);
                mode.ForeColor = Color.FromArgb(161, 34, 34);
                mode.Text = "All partitions and files on this selected drive will be erased. Create Gabulhi (NTFS) plus a 100 MB COUTI (FAT32) boot partition.";
            }
            else ResetFormat();
            UpdateControls();
        }
        bool ConfirmFormat(Disk disk)
        {
            using (var dialog = new Form { Text = "Confirm formatting", ClientSize = new Size(535, 280), FormBorderStyle = FormBorderStyle.FixedDialog, StartPosition = FormStartPosition.CenterParent, MinimizeBox = false, MaximizeBox = false, Font = Font })
            {
                var message = new Label { Left = 20, Top = 18, Width = 495, Height = 125, Text = "Formatting erases ALL partitions and files on:\r\n\r\n" + disk + "\r\n\r\nType FORMAT to enable this option." };
                var entry = new TextBox { Left = 20, Top = 157, Width = 290, MaxLength = 6 };
                var confirm = new Button { Text = "Enable formatting", Left = 263, Top = 218, Width = 153, Height = 32, Enabled = false, DialogResult = DialogResult.OK };
                var cancel = new Button { Text = "Cancel", Left = 428, Top = 218, Width = 86, Height = 32, DialogResult = DialogResult.Cancel };
                entry.TextChanged += delegate { confirm.Enabled = entry.Text == "FORMAT"; };
                dialog.Controls.AddRange(new Control[] { message, entry, confirm, cancel });
                dialog.AcceptButton = confirm; dialog.CancelButton = cancel;
                return dialog.ShowDialog(this) == DialogResult.OK && entry.Text == "FORMAT";
            }
        }
        async Task<Reply> Invoke(string operation, Disk disk, bool erase)
        {
            string operationFolder = Path.Combine(session, Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(operationFolder);
            string request = Path.Combine(operationFolder, "request.json"), response = request + ".result";
            File.WriteAllText(request, json.Serialize(new { Operation = operation, Package = package, Disk = disk, Format = erase, Confirmation = erase ? "FORMAT" : "", Result = response }), new UTF8Encoding(false));
            string windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
            string ps = Path.Combine(windows, Environment.Is64BitOperatingSystem ? @"Sysnative\WindowsPowerShell\v1.0\powershell.exe" : @"System32\WindowsPowerShell\v1.0\powershell.exe");
            var start = new ProcessStartInfo(ps, "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + backend + "\" -Request \"" + request + "\"") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
            return await Task.Run(delegate {
                using (var process = new Process { StartInfo = start })
                {
                    process.Start();
                    Task<string> output = process.StandardOutput.ReadToEndAsync(), errors = process.StandardError.ReadToEndAsync();
                    process.WaitForExit(); Task.WaitAll(output, errors);
                    File.WriteAllText(request + ".log", output.Result + "\r\n" + errors.Result);
                    if (!File.Exists(response)) throw new IOException("The storage service could not finish. " + errors.Result + "\r\nLog: " + request + ".log");
                    Reply reply = json.Deserialize<Reply>(File.ReadAllText(response));
                    if (reply == null || !reply.Ok) throw new IOException(reply == null ? "No storage response." : reply.Message);
                    return reply;
                }
            });
        }
        async Task RefreshDisks()
        {
            busy = true; inspection = null; UpdateControls(); ResetFormat(); status.Text = "Finding available drives...";
            try
            {
                Reply reply = await Invoke("List", null, false);
                suppress = true; disks.Items.Clear();
                if (reply.Disks != null) foreach (Disk disk in reply.Disks) disks.Items.Add(disk);
                disks.SelectedIndex = disks.Items.Count > 0 ? 0 : -1; suppress = false;
                status.Text = disks.Items.Count == 0 ? "No eligible drives found. Connect a USB drive and refresh." : "Ready";
            }
            catch (Exception ex) { ShowError(ex); }
            finally { suppress = false; busy = false; UpdateControls(); }
            if (disks.SelectedItem != null) await InspectSelection();
        }
        async Task InspectSelection()
        {
            int revision = ++selectionRevision;
            Disk disk = disks.SelectedItem as Disk;
            ResetFormat(); inspection = null; inspectedDisk = null; UpdateControls();
            layout.Clear();
            if (disk == null) return;
            busy = true; UpdateControls(); presence.Text = "Checking for Couti..."; status.Text = "Reading the selected drive...";
            try
            {
                Reply reply = await Invoke("Inspect", disk, false);
                if (revision != selectionRevision) return;
                inspection = reply.Inspection; inspectedDisk = disk;
                presence.Text = inspection.Present ? "Couti is present on this drive" : "Couti is not present on this drive";
                presence.ForeColor = inspection.Present ? accent : ink;
                layout.Text = inspection.Layout;
                status.Text = !String.IsNullOrEmpty(inspection.Details) ? inspection.Details : inspection.Present ? "Remove Couti before installing again, or explicitly select Format drive." : "Ready - existing files will be preserved";
            }
            catch (Exception ex) { presence.Text = "Could not read this drive"; ShowError(ex); }
            finally { busy = false; UpdateControls(); }
        }
        async Task Perform(string operation)
        {
            Disk disk = disks.SelectedItem as Disk;
            bool erase = operation == "Install" && format.Checked;
            if (disk == null || inspection == null || Identity(disk) != Identity(inspectedDisk)) return;
            if (erase && formatIdentity != Identity(disk)) { ResetFormat(); return; }
            string question = operation == "Remove"
                ? "Remove Couti from " + disk + "?\r\n\r\nYour data partitions will remain. The removed boot partition becomes unallocated space."
                : erase ? "Final check: erase ALL data on " + disk + "?\r\n\r\nCreate Gabulhi (NTFS) and COUTI (100 MB FAT32)."
                : "Install Couti on " + disk + "?\r\n\r\nPreserve existing files and labels. Use free space, or shrink a supported partition by 100 MB on this drive only.";
            if (MessageBox.Show(this, question, Text, MessageBoxButtons.YesNo, erase ? MessageBoxIcon.Warning : MessageBoxIcon.Question, MessageBoxDefaultButton.Button2) != DialogResult.Yes) return;
            busy = true; UpdateControls(); status.Text = operation == "Remove" ? "Removing Couti..." : "Installing Couti - please keep the drive connected...";
            try { Reply reply = await Invoke(operation, disk, erase); MessageBox.Show(this, reply.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Information); }
            catch (Exception ex) { ShowError(ex); }
            finally { busy = false; ResetFormat(); UpdateControls(); }
            await RefreshDisks();
        }
        void ShowError(Exception ex)
        {
            status.Text = "Operation stopped";
            MessageBox.Show(this, ex.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
    static class Program
    {
        [STAThread] static void Main()
        {
            Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
            try { Application.Run(new InstallerForm()); }
            catch (Exception ex) { MessageBox.Show(ex.Message, "Couti Installer", MessageBoxButtons.OK, MessageBoxIcon.Error); }
        }
    }
}
