# ============================================================
#  Invoke-EdgeManager.ps1
#  CRUD manager for edges.json
#  Create, view, update, and delete edge connections
#
#  USAGE (local):
#    PowerShell -ExecutionPolicy Bypass -File ".\Invoke-EdgeManager.ps1"
#
#  USAGE (live from GitHub):
#    PowerShell -ExecutionPolicy Bypass -File ".\Invoke-EdgeManager.ps1" -FromGitHub
#
#  NOTE: Saving always writes to a LOCAL edges.json file.
#        Push that file to GitHub manually after editing.
# ============================================================

param(
    [switch]$FromGitHub,
    [string]$SchemaPath = ".\schema.json",
    [string]$EdgesPath  = ".\edges.json"
)

$GITHUB_RAW  = "https://raw.githubusercontent.com/NathanielRitchie01/Graph-Theory-Database-Connections/main"
$PAGE_SIZE   = 20
$SAVE_PATH   = ".\edges.json"   # always save locally

# ── Console Helpers ──────────────────────────────────────────

function Write-Header {
    param([string]$Text)
    $line = "=" * 64
    Write-Host ""
    Write-Host $line -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host $line -ForegroundColor Cyan
    Write-Host ""
}

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host "  -- $Text --" -ForegroundColor Yellow
    Write-Host ""
}

function Pause-ForKey {
    Write-Host ""
    Write-Host "  Press any key to continue..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Write-Field {
    param([string]$Label, [string]$Value, [ConsoleColor]$Color = "White")
    Write-Host ("  " + $Label.PadRight(18) + ": ") -ForegroundColor DarkGray -NoNewline
    Write-Host $Value -ForegroundColor $Color
}

function Confirm-Action {
    param([string]$Message, [ConsoleColor]$Color = "Yellow")
    Write-Host ""
    Write-Host "  $Message" -ForegroundColor $Color
    Write-Host "  Type YES to confirm, anything else to cancel: " -ForegroundColor DarkGray -NoNewline
    $r = (Read-Host).Trim()
    return ($r -ieq "YES")
}

# ── JSON Loader ───────────────────────────────────────────────

function Load-Json {
    param([string]$Source, [string]$Name)
    try {
        if ($Source -like "http*") {
            Write-Host "  Fetching $Name..." -ForegroundColor DarkGray -NoNewline
            $ProgressPreference = 'SilentlyContinue'
            $content = (Invoke-WebRequest -Uri $Source -UseBasicParsing -ErrorAction Stop).Content
            Write-Host " OK" -ForegroundColor Green
        } else {
            if (-not (Test-Path $Source)) {
                Write-Host "  ERROR: Cannot find $Name at: $Source" -ForegroundColor Red
                exit 1
            }
            $content = Get-Content $Source -Raw -Encoding UTF8
        }
        return $content | ConvertFrom-Json
    } catch {
        Write-Host ""
        Write-Host "  ERROR loading $Name : $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# ── Save edges.json ───────────────────────────────────────────

function Save-Edges {
    param($EdgesObj)
    try {
        $EdgesObj | ConvertTo-Json -Depth 10 | Set-Content $SAVE_PATH -Encoding UTF8
        Write-Host "  Saved to $SAVE_PATH" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "  ERROR saving: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# ── Paginated List Display ────────────────────────────────────

function Show-PagedList {
    param(
        [object[]]$Items,
        [int]$Page,
        [int]$PageSize,
        [string]$Filter,
        [scriptblock]$RowFormatter,   # takes item + globalIndex, returns string
        [string]$NavHint = ""
    )

    $totalPages = [Math]::Max(1, [Math]::Ceiling($Items.Count / $PageSize))
    $page       = [Math]::Max(0, [Math]::Min($Page, $totalPages - 1))
    $start      = $page * $PageSize
    $end        = [Math]::Min($start + $PageSize, $Items.Count) - 1

    $filterStr = if ($Filter) { "  Filter: '$Filter'   " } else { "  " }
    $pageStr   = "Page $($page+1) of $totalPages  ($($Items.Count) items)"
    Write-Host "$filterStr$pageStr" -ForegroundColor Yellow
    Write-Host ""

    if ($Items.Count -eq 0) {
        Write-Host "  No edges match." -ForegroundColor DarkGray
        Write-Host ""
    } else {
        $pageItems = $Items[$start..$end]
        for ($i = 0; $i -lt $pageItems.Count; $i++) {
            $globalNum = $start + $i + 1
            $row = & $RowFormatter $pageItems[$i] $globalNum
            Write-Host "  $row" -ForegroundColor White
        }
        Write-Host ""
    }

    $nav = @()
    if ($page -gt 0)             { $nav += "PREV" }
    if ($page -lt $totalPages-1) { $nav += "NEXT" }
    $nav += "CLEAR"
    if ($NavHint) { $nav += $NavHint }
    Write-Host ("  Nav: " + ($nav -join "   ")) -ForegroundColor DarkGray
    Write-Host ""

    return $page
}

# ── Table Column Picker (paginated) ──────────────────────────

function Select-TableName {
    param([string[]]$Tables, [string]$Prompt)

    $filter = ""; $page = 0

    while ($true) {
        Clear-Host
        Write-Header "SELECT TABLE"

        $filtered   = @(if ($filter) { $Tables | Where-Object { $_ -like "*$filter*" } } else { $Tables })
        $totalPages = [Math]::Max(1, [Math]::Ceiling($filtered.Count / $PAGE_SIZE))
        $page       = [Math]::Max(0, [Math]::Min($page, $totalPages - 1))

        Show-PagedList -Items $filtered -Page $page -PageSize $PAGE_SIZE -Filter $filter `
            -RowFormatter { param($item,$n) "[$n] $item" } `
            -NavHint "B = back" | Out-Null

        $in = (Read-Host "  $Prompt").Trim()
        if ($in -eq "")         { continue }
        if ($in -ieq "B")       { return $null }
        if ($in -ieq "NEXT")    { $page = [Math]::Min($page+1, $totalPages-1); continue }
        if ($in -ieq "PREV")    { $page = [Math]::Max($page-1, 0); continue }
        if ($in -ieq "CLEAR")   { $filter = ""; $page = 0; continue }

        if ($in -match "^\d+$") {
            $idx = [int]$in - 1
            if ($idx -ge 0 -and $idx -lt $filtered.Count) { return $filtered[$idx] }
            Write-Host "  Invalid number." -ForegroundColor Red
            Start-Sleep -Milliseconds 500
            continue
        }
        $filter = $in; $page = 0
    }
}

function Select-ColumnName {
    param([string[]]$Columns, [string]$TableName, [string]$Prompt)

    $filter = ""; $page = 0

    while ($true) {
        Clear-Host
        Write-Header "SELECT COLUMN  (table: $TableName)"

        $filtered   = @(if ($filter) { $Columns | Where-Object { $_ -like "*$filter*" } } else { $Columns })
        $totalPages = [Math]::Max(1, [Math]::Ceiling($filtered.Count / $PAGE_SIZE))
        $page       = [Math]::Max(0, [Math]::Min($page, $totalPages - 1))

        Show-PagedList -Items $filtered -Page $page -PageSize $PAGE_SIZE -Filter $filter `
            -RowFormatter { param($item,$n) "[$n] $item" } `
            -NavHint "B = back" | Out-Null

        $in = (Read-Host "  $Prompt").Trim()
        if ($in -eq "")         { continue }
        if ($in -ieq "B")       { return $null }
        if ($in -ieq "NEXT")    { $page = [Math]::Min($page+1, $totalPages-1); continue }
        if ($in -ieq "PREV")    { $page = [Math]::Max($page-1, 0); continue }
        if ($in -ieq "CLEAR")   { $filter = ""; $page = 0; continue }

        if ($in -match "^\d+$") {
            $idx = [int]$in - 1
            if ($idx -ge 0 -and $idx -lt $filtered.Count) { return $filtered[$idx] }
            Write-Host "  Invalid number." -ForegroundColor Red
            Start-Sleep -Milliseconds 500
            continue
        }
        $filter = $in; $page = 0
    }
}

# ── Edge Display ──────────────────────────────────────────────

function Show-EdgeDetail {
    param($Edge, [int]$Index)
    Write-Host ""
    Write-Host ("  " + ("-" * 60)) -ForegroundColor DarkGray
    Write-Host "  Edge #$Index" -ForegroundColor Yellow
    Write-Host ("  " + ("-" * 60)) -ForegroundColor DarkGray
    Write-Field "Table A"     $Edge.table_a   Cyan
    Write-Field "Column A"    $Edge.column_a  White
    Write-Field "Table B"     $Edge.table_b   Cyan
    Write-Field "Column B"    $Edge.column_b  White
    Write-Field "Match Type"  $Edge.match_type  $(if ($Edge.match_type -eq "manual") { "Yellow" } else { "DarkGray" })
    Write-Field "Is Mirror"   $Edge.is_mirror.ToString()  $(if ($Edge.is_mirror) { "Magenta" } else { "DarkGray" })
    Write-Field "Notes"       $(if ($Edge.notes) { $Edge.notes } else { "(none)" })  DarkGray
    Write-Host ""
}

# ── Build Edge Filter String ──────────────────────────────────

function Get-EdgeSummary {
    param($Edge, [int]$Num)
    $mirror = if ($Edge.is_mirror) { "[M]" } else { "   " }
    $type   = if ($Edge.match_type -eq "manual") { "[manual]" } else { "        " }
    $a = "$($Edge.table_a).$($Edge.column_a)".PadRight(40)
    $b = "$($Edge.table_b).$($Edge.column_b)".PadRight(40)
    return "[$Num] $mirror $type  $a  <->  $b"
}

function Filter-Edges {
    param([object[]]$Edges, [string]$Filter)
    if (-not $Filter) { return $Edges }
    return @($Edges | Where-Object {
        $_.table_a  -like "*$Filter*" -or
        $_.table_b  -like "*$Filter*" -or
        $_.column_a -like "*$Filter*" -or
        $_.column_b -like "*$Filter*" -or
        $_.notes    -like "*$Filter*" -or
        $_.match_type -like "*$Filter*"
    })
}

# ── VIEW / BROWSE edges ───────────────────────────────────────

function Invoke-ViewEdges {
    param($EdgesObj, $Schema)

    $filter = ""; $page = 0
    $allEdges = [object[]]$EdgesObj.edges

    while ($true) {
        Clear-Host
        Write-Header "EDGES: Browse & Select"

        $filtered   = Filter-Edges -Edges $allEdges -Filter $filter
        $totalPages = [Math]::Max(1, [Math]::Ceiling($filtered.Count / $PAGE_SIZE))
        $page       = [Math]::Max(0, [Math]::Min($page, $totalPages - 1))

        Show-PagedList -Items $filtered -Page $page -PageSize $PAGE_SIZE -Filter $filter `
            -RowFormatter { param($item,$n) Get-EdgeSummary -Edge $item -Num $n } `
            -NavHint "number = inspect   B = back" | Out-Null

        Write-Host "  [M] = mirror edge   [manual] = hand-curated" -ForegroundColor DarkGray
        Write-Host ""

        $in = (Read-Host "  Number to inspect, filter text, NEXT, PREV, CLEAR, or B").Trim()
        if ($in -eq "")       { continue }
        if ($in -ieq "B")     { return $EdgesObj }
        if ($in -ieq "NEXT")  { $page = [Math]::Min($page+1, $totalPages-1); continue }
        if ($in -ieq "PREV")  { $page = [Math]::Max($page-1, 0); continue }
        if ($in -ieq "CLEAR") { $filter = ""; $page = 0; continue }

        if ($in -match "^\d+$") {
            $globalIdx = [int]$in - 1
            if ($globalIdx -ge 0 -and $globalIdx -lt $filtered.Count) {
                $edge   = $filtered[$globalIdx]
                $result = Invoke-InspectEdge -Edge $edge -GlobalIndex ([int]$in) -EdgesObj $EdgesObj -Schema $Schema
                $EdgesObj = $result
                $allEdges = [object[]]$EdgesObj.edges
                $filtered = Filter-Edges -Edges $allEdges -Filter $filter
            } else {
                Write-Host "  Invalid number." -ForegroundColor Red
                Start-Sleep -Milliseconds 500
            }
            continue
        }

        $filter = $in; $page = 0
    }
}

# ── INSPECT a single edge (view / edit / delete) ──────────────

function Invoke-InspectEdge {
    param($Edge, [int]$GlobalIndex, $EdgesObj, $Schema)

    while ($true) {
        Clear-Host
        Write-Header "EDGE DETAIL"
        Show-EdgeDetail -Edge $Edge -Index $GlobalIndex

        Write-Host "  [U]  Update this edge" -ForegroundColor White
        Write-Host "  [D]  Delete this edge" -ForegroundColor White
        Write-Host "  [B]  Back to list" -ForegroundColor White
        Write-Host ""

        $choice = (Read-Host "  Select").Trim().ToUpper()

        switch ($choice) {
            "U" {
                $EdgesObj = Invoke-UpdateEdge -Edge $Edge -EdgesObj $EdgesObj -Schema $Schema
                # Refresh edge reference after update
                $Edge = $EdgesObj.edges | Where-Object {
                    $_.table_a -eq $Edge.table_a -and $_.column_a -eq $Edge.column_a -and
                    $_.table_b -eq $Edge.table_b -and $_.column_b -eq $Edge.column_b
                } | Select-Object -First 1
                if (-not $Edge) { return $EdgesObj }   # edge was replaced/removed
            }
            "D" {
                $EdgesObj = Invoke-DeleteEdge -Edge $Edge -EdgesObj $EdgesObj
                return $EdgesObj
            }
            "B" { return $EdgesObj }
        }
    }
}

# ── DELETE edge ───────────────────────────────────────────────

function Invoke-DeleteEdge {
    param($Edge, $EdgesObj)

    Clear-Host
    Write-Header "DELETE EDGE"
    Show-EdgeDetail -Edge $Edge -Index 0

    if (Confirm-Action "Are you sure you want to DELETE this edge? This cannot be undone." "Red") {
        $EdgesObj.edges = [System.Collections.Generic.List[object]]($EdgesObj.edges | Where-Object {
            -not (
                $_.table_a  -eq $Edge.table_a  -and
                $_.column_a -eq $Edge.column_a -and
                $_.table_b  -eq $Edge.table_b  -and
                $_.column_b -eq $Edge.column_b
            )
        })
        $EdgesObj.meta.auto_edge_count = $EdgesObj.edges.Count
        if (Save-Edges -EdgesObj $EdgesObj) {
            Write-Host "  Edge deleted." -ForegroundColor Green
        }
        Start-Sleep -Seconds 1
    } else {
        Write-Host "  Cancelled." -ForegroundColor DarkGray
        Start-Sleep -Milliseconds 500
    }
    return $EdgesObj
}

# ── UPDATE edge ───────────────────────────────────────────────

function Invoke-UpdateEdge {
    param($Edge, $EdgesObj, $Schema)

    $allTables = @($Schema.tables.PSObject.Properties.Name | Sort-Object)

    # Work on a copy
    $updated = [PSCustomObject]@{
        table_a    = $Edge.table_a
        column_a   = $Edge.column_a
        table_b    = $Edge.table_b
        column_b   = $Edge.column_b
        match_type = $Edge.match_type
        is_mirror  = $Edge.is_mirror
        notes      = $Edge.notes
    }

    $fields = @("table_a","column_a","table_b","column_b","match_type","is_mirror","notes")
    $fi     = 0

    while ($fi -lt $fields.Count) {
        $field = $fields[$fi]
        Clear-Host
        Write-Header "UPDATE EDGE  (field $($fi+1) of $($fields.Count))"

        Write-Host "  Current edge:" -ForegroundColor DarkGray
        Show-EdgeDetail -Edge $updated -Index 0
        Write-Host "  Editing: " -ForegroundColor Yellow -NoNewline
        Write-Host $field -ForegroundColor Cyan
        Write-Host "  Current value: " -ForegroundColor DarkGray -NoNewline
        Write-Host ($updated.$field) -ForegroundColor White
        Write-Host ""
        Write-Host "  Press ENTER to keep current value, B to go back a field, SKIP to finish early." -ForegroundColor DarkGray
        Write-Host ""

        switch ($field) {
            "table_a" {
                Write-Host "  Select new Table A (or press ENTER to keep):" -ForegroundColor DarkGray
                $val = Select-TableName -Tables $allTables -Prompt "Table A (or ENTER/B/SKIP)"
                if ($val -eq "SKIP") { $fi = $fields.Count; continue }
                if ($null -ne $val)  { $updated.table_a = $val }
            }
            "column_a" {
                $cols = @(($Schema.tables.($updated.table_a).columns | ForEach-Object { $_.name }) | Sort-Object)
                $val  = Select-ColumnName -Columns $cols -TableName $updated.table_a -Prompt "Column A (or ENTER/B/SKIP)"
                if ($val -eq "SKIP") { $fi = $fields.Count; continue }
                if ($null -ne $val)  { $updated.column_a = $val }
            }
            "table_b" {
                $val = Select-TableName -Tables $allTables -Prompt "Table B (or ENTER/B/SKIP)"
                if ($val -eq "SKIP") { $fi = $fields.Count; continue }
                if ($null -ne $val)  { $updated.table_b = $val }
            }
            "column_b" {
                $cols = @(($Schema.tables.($updated.table_b).columns | ForEach-Object { $_.name }) | Sort-Object)
                $val  = Select-ColumnName -Columns $cols -TableName $updated.table_b -Prompt "Column B (or ENTER/B/SKIP)"
                if ($val -eq "SKIP") { $fi = $fields.Count; continue }
                if ($null -ne $val)  { $updated.column_b = $val }
            }
            "match_type" {
                Write-Host "  Options: exact, manual" -ForegroundColor DarkGray
                $val = (Read-Host "  match_type (ENTER to keep, SKIP)").Trim()
                if ($val -ieq "SKIP") { $fi = $fields.Count; continue }
                if ($val -ieq "B")    { $fi = [Math]::Max(0, $fi-2); continue }
                if ($val -in @("exact","manual","")) { if ($val) { $updated.match_type = $val } }
                else { Write-Host "  Must be 'exact' or 'manual'." -ForegroundColor Red; Start-Sleep -Seconds 1; continue }
            }
            "is_mirror" {
                Write-Host "  Options: true, false" -ForegroundColor DarkGray
                $val = (Read-Host "  is_mirror (ENTER to keep, SKIP)").Trim()
                if ($val -ieq "SKIP") { $fi = $fields.Count; continue }
                if ($val -ieq "B")    { $fi = [Math]::Max(0, $fi-2); continue }
                if ($val -ieq "true")  { $updated.is_mirror = $true }
                elseif ($val -ieq "false") { $updated.is_mirror = $false }
                elseif ($val -ne "") {
                    Write-Host "  Must be 'true' or 'false'." -ForegroundColor Red
                    Start-Sleep -Seconds 1; continue
                }
            }
            "notes" {
                $val = (Read-Host "  notes (ENTER to keep, SKIP, or type new note)").Trim()
                if ($val -ieq "SKIP") { $fi = $fields.Count; continue }
                if ($val -ieq "B")    { $fi = [Math]::Max(0, $fi-2); continue }
                if ($val -ne "") { $updated.notes = $val }
            }
        }
        $fi++
    }

    # Final confirmation
    Clear-Host
    Write-Header "UPDATE EDGE: CONFIRM"
    Write-Host "  BEFORE:" -ForegroundColor DarkGray
    Show-EdgeDetail -Edge $Edge    -Index 0
    Write-Host "  AFTER:" -ForegroundColor Yellow
    Show-EdgeDetail -Edge $updated -Index 0

    if (Confirm-Action "Save these changes?") {
        # Replace in list
        $newList = [System.Collections.Generic.List[object]]::new()
        foreach ($e in $EdgesObj.edges) {
            if ($e.table_a -eq $Edge.table_a -and $e.column_a -eq $Edge.column_a -and
                $e.table_b -eq $Edge.table_b -and $e.column_b -eq $Edge.column_b) {
                $newList.Add($updated)
            } else {
                $newList.Add($e)
            }
        }
        $EdgesObj.edges = $newList
        if (Save-Edges -EdgesObj $EdgesObj) {
            Write-Host "  Edge updated." -ForegroundColor Green
        }
        Start-Sleep -Seconds 1
    } else {
        Write-Host "  Update cancelled." -ForegroundColor DarkGray
        Start-Sleep -Milliseconds 500
    }

    return $EdgesObj
}

# ── CREATE new edge ───────────────────────────────────────────

function Invoke-CreateEdge {
    param($EdgesObj, $Schema)

    $allTables = @($Schema.tables.PSObject.Properties.Name | Sort-Object)

    Clear-Host
    Write-Header "CREATE NEW EDGE"
    Write-Host "  Walk through each field. B at any point cancels." -ForegroundColor DarkGray
    Write-Host ""

    # ── Step 1: Table A
    Write-Host "  STEP 1 of 7 - Select Table A" -ForegroundColor Yellow
    $tableA = Select-TableName -Tables $allTables -Prompt "Select Table A"
    if ($null -eq $tableA) { Write-Host "  Cancelled." -ForegroundColor DarkGray; Start-Sleep -Milliseconds 500; return $EdgesObj }

    # ── Step 2: Column A
    Clear-Host
    Write-Header "CREATE NEW EDGE"
    Write-Field "Table A" $tableA Cyan
    Write-Host ""
    Write-Host "  STEP 2 of 7 - Select Column A  (from $tableA)" -ForegroundColor Yellow
    $cols = @(($Schema.tables.$tableA.columns | ForEach-Object { $_.name }) | Sort-Object)
    $colA = Select-ColumnName -Columns $cols -TableName $tableA -Prompt "Select Column A"
    if ($null -eq $colA) { Write-Host "  Cancelled." -ForegroundColor DarkGray; Start-Sleep -Milliseconds 500; return $EdgesObj }

    # ── Step 3: Table B
    Clear-Host
    Write-Header "CREATE NEW EDGE"
    Write-Field "Table A"  $tableA Cyan
    Write-Field "Column A" $colA   White
    Write-Host ""
    Write-Host "  STEP 3 of 7 - Select Table B" -ForegroundColor Yellow
    $tableB = Select-TableName -Tables ($allTables | Where-Object { $_ -ne $tableA }) -Prompt "Select Table B"
    if ($null -eq $tableB) { Write-Host "  Cancelled." -ForegroundColor DarkGray; Start-Sleep -Milliseconds 500; return $EdgesObj }

    # ── Step 4: Column B
    Clear-Host
    Write-Header "CREATE NEW EDGE"
    Write-Field "Table A"  $tableA Cyan
    Write-Field "Column A" $colA   White
    Write-Field "Table B"  $tableB Cyan
    Write-Host ""
    Write-Host "  STEP 4 of 7 - Select Column B  (from $tableB)" -ForegroundColor Yellow
    $cols = @(($Schema.tables.$tableB.columns | ForEach-Object { $_.name }) | Sort-Object)
    $colB = Select-ColumnName -Columns $cols -TableName $tableB -Prompt "Select Column B"
    if ($null -eq $colB) { Write-Host "  Cancelled." -ForegroundColor DarkGray; Start-Sleep -Milliseconds 500; return $EdgesObj }

    # ── Step 5: match_type
    Clear-Host
    Write-Header "CREATE NEW EDGE"
    Write-Field "Table A"  $tableA Cyan
    Write-Field "Column A" $colA   White
    Write-Field "Table B"  $tableB Cyan
    Write-Field "Column B" $colB   White
    Write-Host ""
    Write-Host "  STEP 5 of 7 - Match Type" -ForegroundColor Yellow
    Write-Host "  exact  = columns have the same name (auto-detected)" -ForegroundColor DarkGray
    Write-Host "  manual = columns have different names (hand-curated)" -ForegroundColor DarkGray
    Write-Host ""
    $matchType = ""
    while ($matchType -notin @("exact","manual")) {
        $matchType = (Read-Host "  Type 'exact' or 'manual'").Trim().ToLower()
        if ($matchType -ieq "B") { Write-Host "  Cancelled." -ForegroundColor DarkGray; Start-Sleep -Milliseconds 500; return $EdgesObj }
    }

    # ── Step 6: is_mirror
    Clear-Host
    Write-Header "CREATE NEW EDGE"
    Write-Field "Table A"    $tableA    Cyan
    Write-Field "Column A"   $colA      White
    Write-Field "Table B"    $tableB    Cyan
    Write-Field "Column B"   $colB      White
    Write-Field "Match Type" $matchType White
    Write-Host ""
    Write-Host "  STEP 6 of 7 - Is Mirror Edge?" -ForegroundColor Yellow
    Write-Host "  A mirror edge connects an x_ table to its mi_ equivalent." -ForegroundColor DarkGray

    # Auto-suggest mirror status
    $autoMirror = ($tableA -match "^x_(.+)$" -and $tableB -eq "mi_$($Matches[1])") -or
                  ($tableB -match "^x_(.+)$" -and $tableA -eq "mi_$($Matches[1])")
    if ($autoMirror) {
        Write-Host "  (Auto-detected as a mirror pair)" -ForegroundColor Magenta
    }
    Write-Host ""

    $isMirror = $autoMirror
    $mirrorIn = (Read-Host "  Is mirror? (true/false, ENTER = $($autoMirror.ToString().ToLower()))").Trim()
    if ($mirrorIn -ieq "true")  { $isMirror = $true }
    if ($mirrorIn -ieq "false") { $isMirror = $false }

    # ── Step 7: notes
    Clear-Host
    Write-Header "CREATE NEW EDGE"
    Write-Field "Table A"    $tableA    Cyan
    Write-Field "Column A"   $colA      White
    Write-Field "Table B"    $tableB    Cyan
    Write-Field "Column B"   $colB      White
    Write-Field "Match Type" $matchType White
    Write-Field "Is Mirror"  $isMirror.ToString() $(if ($isMirror) { "Magenta" } else { "DarkGray" })
    Write-Host ""
    Write-Host "  STEP 7 of 7 - Notes (optional)" -ForegroundColor Yellow
    Write-Host "  Describe why this edge exists, e.g. 'legacy naming pre-2015 upgrade'" -ForegroundColor DarkGray
    Write-Host ""
    $notes = (Read-Host "  Notes (or ENTER to leave blank)").Trim()

    # ── Final confirmation
    $newEdge = [PSCustomObject]@{
        table_a    = $tableA
        column_a   = $colA
        table_b    = $tableB
        column_b   = $colB
        match_type = $matchType
        is_mirror  = $isMirror
        notes      = $notes
    }

    Clear-Host
    Write-Header "CREATE NEW EDGE: CONFIRM"
    Show-EdgeDetail -Edge $newEdge -Index 0

    # Check for duplicate
    $duplicate = $EdgesObj.edges | Where-Object {
        (($_.table_a -eq $tableA -and $_.column_a -eq $colA -and $_.table_b -eq $tableB -and $_.column_b -eq $colB) -or
         ($_.table_a -eq $tableB -and $_.column_a -eq $colB -and $_.table_b -eq $tableA -and $_.column_b -eq $colA))
    } | Select-Object -First 1

    if ($duplicate) {
        Write-Host "  WARNING: A similar edge already exists:" -ForegroundColor Yellow
        Show-EdgeDetail -Edge $duplicate -Index 0
        if (-not (Confirm-Action "Create anyway?" "Yellow")) {
            Write-Host "  Cancelled." -ForegroundColor DarkGray
            Start-Sleep -Milliseconds 500
            return $EdgesObj
        }
    } else {
        if (-not (Confirm-Action "Create this edge?")) {
            Write-Host "  Cancelled." -ForegroundColor DarkGray
            Start-Sleep -Milliseconds 500
            return $EdgesObj
        }
    }

    $EdgesObj.edges += $newEdge
    $EdgesObj.meta.auto_edge_count = $EdgesObj.edges.Count

    if (Save-Edges -EdgesObj $EdgesObj) {
        Write-Host "  Edge created. Total edges: $($EdgesObj.edges.Count)" -ForegroundColor Green
    }
    Start-Sleep -Seconds 1
    return $EdgesObj
}

# ── Main Menu ─────────────────────────────────────────────────

function Show-MainMenu {
    param([int]$EdgeCount)
    Write-Header "MIS EDGE MANAGER"
    Write-Host "  Total edges loaded : $EdgeCount" -ForegroundColor Gray
    Write-Host "  Save location      : $SAVE_PATH" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [1]  Browse / Edit edges   - View, search, update or delete" -ForegroundColor White
    Write-Host "  [2]  Create new edge       - Add a manual connection" -ForegroundColor White
    Write-Host "  [Q]  Quit" -ForegroundColor White
    Write-Host ""
    return Read-Host "  Select option"
}

# ── Entry Point ───────────────────────────────────────────────

Clear-Host
Write-Host ""
Write-Host "  MIS Edge Manager" -ForegroundColor Cyan
Write-Host "  Loading data..." -ForegroundColor DarkGray
Write-Host ""

if ($FromGitHub) {
    $schemaSource = "$GITHUB_RAW/schema.json"
    $edgesSource  = "$GITHUB_RAW/edges.json"
} else {
    $schemaSource = $SchemaPath
    $edgesSource  = $EdgesPath
}

$schema   = Load-Json -Source $schemaSource -Name "schema.json"
$edgesObj = Load-Json -Source $edgesSource  -Name "edges.json"

# Convert edges array to a mutable list
$edgesObj.edges = [System.Collections.Generic.List[object]]($edgesObj.edges)

while ($true) {
    Clear-Host
    $choice = Show-MainMenu -EdgeCount $edgesObj.edges.Count

    switch ($choice.ToUpper()) {
        "1" {
            Clear-Host
            $edgesObj = Invoke-ViewEdges -EdgesObj $edgesObj -Schema $schema
        }
        "2" {
            Clear-Host
            $edgesObj = Invoke-CreateEdge -EdgesObj $edgesObj -Schema $schema
        }
        "Q" {
            Write-Host ""
            Write-Host "  Goodbye. Remember to push edges.json to GitHub if you made changes." -ForegroundColor Cyan
            Write-Host ""
            exit
        }
        default {
            Write-Host "  Invalid option." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}