# === DaUfooo´s Live Ransomware Viewer ===

# === Konfiguration ===
$APIBase = 'https://api.ransomware.live/v2'
$Token = 'INSERT-YOUR-API-KEY@https://www.ransomware.live/'

# === WinForms laden ===
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Hilfs-Funktion: API aufrufen
function Invoke-RWApi {
    param([string]$Path)
    $url = "$APIBase$Path"
    try {
        $headers = @{ Authorization = "Bearer $Token" }
        $resp = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -ErrorAction Stop
        return $resp
    } catch {
        try {
            $sep = if ($url -match '\?') { '&' } else { '?' }
            $fb = "$url$sep`token=$([System.Web.HttpUtility]::UrlEncode($Token))"
            $resp2 = Invoke-RestMethod -Uri $fb -Method Get -ErrorAction Stop
            return $resp2
        } catch { throw $_ }
    }
}

# Sichere String-Anzeige
function SafeStr([object]$o){
    if ($null -eq $o) { return '' }
    return [string]$o
}

# === GUI aufbauen ===
$form = New-Object System.Windows.Forms.Form
$form.Text = "DaUfooo´s Ransomware Live Viewer"
$form.Size = New-Object System.Drawing.Size(1280,1024)
$form.StartPosition = "CenterScreen"
$form.MinimizeBox = $true
$form.MaximizeBox = $true

# Toolbar panel
$panel = New-Object System.Windows.Forms.Panel
$panel.Dock = 'Top'
$panel.Height = 56
$panel.BackColor = [System.Drawing.Color]::FromArgb(83,83,153)
$form.Controls.Add($panel)

# Search box
$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Width = 300
$txtSearch.Location = New-Object System.Drawing.Point(12,14)
$txtSearch.PlaceholderText = "Search victims or group"
$panel.Controls.Add($txtSearch)

# Country filter
$cbCountry = New-Object System.Windows.Forms.ComboBox
$cbCountry.Location = New-Object System.Drawing.Point(330,12)
$cbCountry.Width = 120
$cbCountry.DropDownStyle = 'DropDownList'
$cbCountry.Items.AddRange(@('','AT','DE','US','GB','CN'))
$cbCountry.SelectedIndex = 0
$panel.Controls.Add($cbCountry)

# Load button
$btnLoad = New-Object System.Windows.Forms.Button
$btnLoad.Text = "Load Recent"
$btnLoad.Location = New-Object System.Drawing.Point(464,10)
$btnLoad.Width = 100
$panel.Controls.Add($btnLoad)

# Export CSV
$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Text = "Export CSV"
$btnExport.Location = New-Object System.Drawing.Point(570,10)
$btnExport.Width = 90
$panel.Controls.Add($btnExport)

# Status label
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.AutoSize = $true
$lblStatus.Location = New-Object System.Drawing.Point(670,16)
$lblStatus.ForeColor = [System.Drawing.Color]::LightGray
$lblStatus.Text = "Ready"
$panel.Controls.Add($lblStatus)

# Data grid
$dataGrid = New-Object System.Windows.Forms.DataGridView
$dataGrid.Dock = 'Fill'
$dataGrid.ReadOnly = $true
$dataGrid.SelectionMode = 'FullRowSelect'
$dataGrid.AutoSizeColumnsMode = 'Fill'
$dataGrid.MultiSelect = $false
$dataGrid.AllowUserToAddRows = $false
$dataGrid.RowHeadersVisible = $false

# Details panel (SplitContainer)
$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock = 'Fill'
$split.Orientation = 'Vertical'
$split.SplitterDistance = 1000
$split.Panel1.Controls.Add($dataGrid)
$form.Controls.Add($split)
$form.Controls.SetChildIndex($split,0)

# Rechts: FlowLayoutPanel für Textdetails (ohne Bilder)
$global:flowDetails = New-Object System.Windows.Forms.FlowLayoutPanel
$global:flowDetails.Dock = 'Fill'
$global:flowDetails.AutoScroll = $true
$global:flowDetails.WrapContents = $false
$global:flowDetails.FlowDirection = 'TopDown'
$split.Panel2.Controls.Add($global:flowDetails)

# Buttons rechts
$btnOpenPress = New-Object System.Windows.Forms.Button
$btnOpenPress.Text = "Open Press Links"
$btnOpenPress.Dock = 'Bottom'
$split.Panel2.Controls.Add($btnOpenPress)

$btnShowUpdates = New-Object System.Windows.Forms.Button
$btnShowUpdates.Text = "Show Updates"
$btnShowUpdates.Dock = 'Bottom'
$split.Panel2.Controls.Add($btnShowUpdates)

# Interner Speicher für Victims
$global:Victims = @()

# === Funktionen: DataGrid füllen ===
function Render-VictimsGrid {
    param([array]$arr)
    $dataGrid.Columns.Clear()
    $dataGrid.Rows.Clear()

    # Columns
    $cols = @(
        @{Name='victim';Header='Victim'},
        @{Name='group';Header='Group'},
        @{Name='attackdate';Header='AttackDate'},
        @{Name='country';Header='Country';Width=60}
    )
    foreach ($c in $cols) {
        $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
        $col.Name = $c.Name
        $col.HeaderText = $c.Header
        if ($c.Width) { $col.Width = $c.Width }
        $dataGrid.Columns.Add($col) > $null
    }

    # Rows
    foreach ($v in $arr) {
        $victim = SafeStr $v.victim
        $group  = SafeStr $v.group
        $date   = SafeStr $v.attackdate
        $country= SafeStr $v.country

        $idx = $dataGrid.Rows.Add($victim, $group, $date, $country)
        $dataGrid.Rows[$idx].Tag = $v
    }

    $lblStatus.Text = "Loaded $($arr.Count) records"
}

# === Funktion: Load Recent Victims + Filter ===
function Load-RecentVictims {
    $lblStatus.Text = "Loading..."
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    try {
        $resp = Invoke-RWApi -Path '/recentvictims'

        # Normalisierung
        if ($resp -is [System.Collections.IEnumerable] -and -not ($resp -is [string])) { $arr = @($resp) }
        elseif ($resp.PSObject.Properties.Name -contains 'data') { $arr = @($resp.data) }
        elseif ($resp.PSObject.Properties.Name -contains 'victims') { $arr = @($resp.victims) }
        else { $arr = @($resp) }

        # Filter: Search + Country
        $search = $txtSearch.Text.Trim().ToLower()
        $country = $cbCountry.SelectedItem
        if ($country -eq '') { $country = $null }

        $filtered = @()
        foreach ($it in $arr) {
            $ok = $true
            if ($country -and (-not $it.country -or $it.country.ToUpper() -ne $country.ToUpper())) { $ok = $false }
            if ($ok -and $search) {
                if ((-not (SafeStr $it.victim).ToLower().Contains($search)) -and (-not (SafeStr $it.group).ToLower().Contains($search))) { $ok = $false }
            }
            if ($ok) { $filtered += $it }
        }

        $global:Victims = $filtered
        Render-VictimsGrid -arr $filtered
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Fehler beim Laden:`n$($_.Exception.Message)","Fehler",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        $lblStatus.Text = "Fehler: $($_.Exception.Message)"
    } finally {
        $form.Cursor = [System.Windows.Forms.Cursors]::Default
    }
}

# === UI Events ===
$btnLoad.Add_Click({ Load-RecentVictims })
$txtSearch.Add_TextChanged({ Load-RecentVictims })
$cbCountry.Add_SelectedIndexChanged({ Load-RecentVictims })

# Erstes Laden beim Start
try { Load-RecentVictims } catch {}

# === DataGrid Selection → Details anzeigen (Text only) ===


$dataGrid.add_SelectionChanged({
    if ($dataGrid.SelectedRows.Count -eq 0) { return }
    $row = $dataGrid.SelectedRows[0]
    $rec = $row.Tag
    if (-not $rec) { return }

    # FlowPanel leeren
    $global:flowDetails.Controls.Clear()

    # RichTextBox für Textdetails
    $rtb = New-Object System.Windows.Forms.RichTextBox
    $rtb.ReadOnly = $true
    $rtb.Width = $split.Panel2.Width - 25
    $rtb.Font = New-Object System.Drawing.Font("Consolas",10)
    $rtb.ScrollBars = 'None'  # Keine Scrollbars, FlowPanel übernimmt bei Bedarf

    # Text zusammensetzen
    $text = ""
    function Format-DateTime($dt) {
        try { return [DateTime]::Parse($dt).ToString("HH:mm | dd-MM-yyyy") } catch { return $dt }
    }

    $text += "Victim Details`r`n====================`r`n"

    foreach ($prop in $rec.PSObject.Properties) {
        $val = $rec.$($prop.Name)
        if ($null -eq $val) { continue }

        switch -regex ($prop.Name) {
            'attackdate' { $val = Format-DateTime $val; $text += "[$($prop.Name)] : $val`r`n" }
            'infostealer' {
                $text += "[$($prop.Name)] :`r`n"
                if ($val -is [System.Collections.IDictionary]) {
                    foreach ($k in $val.Keys) { $text += "    $k : $($val[$k])`r`n" }
                } elseif ($val -is [System.Collections.IEnumerable] -and -not ($val -is [string])) {
                    foreach ($item in $val) { $text += "    " + (SafeStr $item) + "`r`n" }
                } else { $text += "    " + (SafeStr $val) + "`r`n" }
            }
            'updates' {
                $text += "[$($prop.Name)] :`r`n"
                if ($val -is [System.Collections.IEnumerable] -and -not ($val -is [string])) {
                    foreach ($u in $val) { $text += "    $u`r`n" }
                } else { $text += "    " + (SafeStr $val) + "`r`n" }
            }
            'press' {
                $text += "[$($prop.Name)] :`r`n"
                if ($val -is [System.Collections.IEnumerable] -and -not ($val -is [string])) {
                    foreach ($p in $val) {
                        if ($p -is [string]) { $text += "    $p`r`n" }
                        elseif ($p.url) { $text += "    $($p.url)`r`n" }
                    }
                } else { $text += "    " + (SafeStr $val) + "`r`n" }
            }
            default { $text += "[$($prop.Name)] : $($val)`r`n" }
        }
    }

    $rtb.Text = $text

    # Höhe der RichTextBox automatisch an Text anpassen
    $rtb.Height = [Math]::Min($rtb.GetPositionFromCharIndex($rtb.Text.Length - 1).Y + 30, $split.Panel2.Height - 50)

    $global:flowDetails.Controls.Add($rtb)
})




# === Button: Press Links im Browser öffnen ===
$btnOpenPress.Add_Click({
    if ($dataGrid.SelectedRows.Count -eq 0) { return }
    $rec = $dataGrid.SelectedRows[0].Tag
    if (-not $rec -or -not $rec.press) { return }

    $pressLinks = @()
    if ($rec.press -is [string]) { $pressLinks += $rec.press }
    elseif ($rec.press -is [System.Collections.IEnumerable]) {
        foreach ($p in $rec.press) {
            if ($p -is [string]) { $pressLinks += $p }
            elseif ($p.url) { $pressLinks += $p.url }
        }
    }

    foreach ($url in $pressLinks) { Start-Process $url }
})

# === Button: Updates anzeigen ===
$btnShowUpdates.Add_Click({
    if ($dataGrid.SelectedRows.Count -eq 0) { return }
    $rec = $dataGrid.SelectedRows[0].Tag
    if (-not $rec -or -not $rec.updates) { 
        [System.Windows.Forms.MessageBox]::Show("Keine Updates.","Info",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return 
    }

    $lines = @()
    if ($rec.updates -is [System.Collections.IEnumerable]) { foreach ($x in $rec.updates) { $lines += SafeStr $x } }
    else { $lines += SafeStr $rec.updates }
    [System.Windows.Forms.MessageBox]::Show(($lines -join "`r`n`r`n"), "Updates", [System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
})

# === Button: CSV Export ===
$btnExport.Add_Click({
    if (-not $global:Victims -or $global:Victims.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Keine Daten zum Exportieren.","Info",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = "CSV file|*.csv"
    $sfd.FileName = "ransomware_victims.csv"
    if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $csv = @()
    foreach ($v in $global:Victims) {
        $csv += [PSCustomObject]@{
            victim = SafeStr $v.victim
            group = SafeStr $v.group
            attackdate = SafeStr $v.attackdate
            country = SafeStr $v.country
            press = if ($v.press) { ($v.press -join ' | ') } else { '' }
        }
    }
    $csv | Export-Csv -Path $sfd.FileName -NoTypeInformation -Encoding UTF8
    [System.Windows.Forms.MessageBox]::Show("Export gespeichert:`n$sfd.FileName","Export",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
})

# === Formular starten ===
[void]$form.ShowDialog()
