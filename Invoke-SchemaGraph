# ============================================================
#  Invoke-SchemaGraph.ps1
#  Interactive graph traversal tool for MIS database schema
#
#  USAGE:
#    PowerShell -ExecutionPolicy Bypass -File ".\Invoke-SchemaGraph.ps1"
#
#  REQUIRES (in same folder or specify paths below):
#    schema.json
#    edges.json
#    config.json
# ============================================================

param(
    [string]$SchemaPath = ".\schema.json",
    [string]$EdgesPath  = ".\edges.json",
    [string]$ConfigPath = ".\config.json"
)

# ── Console Helpers ──────────────────────────────────────────

function Write-Header {
    param([string]$Text)
    $line = "=" * 60
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

function Write-TableRow {
    param([string]$Col1, [string]$Col2, [string]$Col3 = "", [ConsoleColor]$Color = "White")
    $c1 = $Col1.PadRight(35)
    $c2 = $Col2.PadRight(25)
    Write-Host "  $c1 $c2 $Col3" -ForegroundColor $Color
}

function Pause-ForKey {
    Write-Host ""
    Write-Host "  Press any key to continue..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

# ── Load JSON Files ──────────────────────────────────────────

function Load-JsonFile {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path $Path)) {
        Write-Host "  ERROR: Cannot find $Name at: $Path" -ForegroundColor Red
        Write-Host "  Make sure you run Build-GraphFiles.ps1 first." -ForegroundColor Yellow
        exit 1
    }
    try {
        return Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Host "  ERROR: Failed to parse $Name - $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# ── Build Adjacency Graph ────────────────────────────────────

function Build-Graph {
    param($Edges, [bool]$IncludeMirror)

    # graph is a hashtable: tableName -> list of @{Table, ColumnA, ColumnB, MatchType}
    $graph = @{}

    foreach ($edge in $Edges.edges) {
        if (-not $IncludeMirror -and $edge.is_mirror) { continue }

        $a = $edge.table_a
        $b = $edge.table_b

        if (-not $graph.ContainsKey($a)) { $graph[$a] = [System.Collections.Generic.List[object]]::new() }
        if (-not $graph.ContainsKey($b)) { $graph[$b] = [System.Collections.Generic.List[object]]::new() }

        $graph[$a].Add([PSCustomObject]@{
            Table    = $b
            ColumnA  = $edge.column_a
            ColumnB  = $edge.column_b
            Type     = $edge.match_type
            IsMirror = $edge.is_mirror
        })

        $graph[$b].Add([PSCustomObject]@{
            Table    = $a
            ColumnA  = $edge.column_b
            ColumnB  = $edge.column_a
            Type     = $edge.match_type
            IsMirror = $edge.is_mirror
        })
    }

    return $graph
}

# ── BFS Shortest Path ────────────────────────────────────────

function Find-ShortestPath {
    param($Graph, [string]$Start, [string]$End)

    if ($Start -eq $End) {
        return @{ Found = $true; Path = @($Start); Edges = @() }
    }

    if (-not $Graph.ContainsKey($Start)) {
        return @{ Found = $false; Reason = "Start table '$Start' has no edges in graph" }
    }

    if (-not $Graph.ContainsKey($End)) {
        return @{ Found = $false; Reason = "Destination table '$End' has no edges in graph" }
    }

    # BFS
    $visited  = @{ $Start = $true }
    $queue    = [System.Collections.Generic.Queue[object]]::new()
    $queue.Enqueue([PSCustomObject]@{
        Table = $Start
        Path  = [System.Collections.Generic.List[string]]::new()
        Edges = [System.Collections.Generic.List[object]]::new()
    })
    ($queue.Peek()).Path.Add($Start)

    $maxDepth = 8

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()

        if ($current.Path.Count -gt $maxDepth) {
            return @{ Found = $false; Reason = "No path found within $maxDepth hops" }
        }

        if (-not $Graph.ContainsKey($current.Table)) { continue }

        foreach ($neighbour in $Graph[$current.Table]) {
            if ($visited.ContainsKey($neighbour.Table)) { continue }
            $visited[$neighbour.Table] = $true

            $newPath  = [System.Collections.Generic.List[string]]::new($current.Path)
            $newEdges = [System.Collections.Generic.List[object]]::new($current.Edges)
            $newPath.Add($neighbour.Table)
            $newEdges.Add($neighbour)

            if ($neighbour.Table -eq $End) {
                return @{ Found = $true; Path = $newPath; Edges = $newEdges }
            }

            $queue.Enqueue([PSCustomObject]@{
                Table = $neighbour.Table
                Path  = $newPath
                Edges = $newEdges
            })
        }
    }

    return @{ Found = $false; Reason = "No path exists between these tables" }
}

# ── Display Path Result ──────────────────────────────────────

function Show-Path {
    param($Result, [string]$Start, [string]$End)

    if (-not $Result.Found) {
        Write-Host ""
        Write-Host "  No path found: $($Result.Reason)" -ForegroundColor Red
        Write-Host ""
        Write-Host "  You may need to add a manual edge in edges.json" -ForegroundColor Yellow
        Write-Host "  to connect these tables via a mismatched column name." -ForegroundColor Yellow
        return
    }

    $hops = $Result.Path.Count - 1
    Write-Host ""
    Write-Host "  Path found: $hops hop(s)" -ForegroundColor Green
    Write-Host ""

    # Build the visual path string
    $pathStr = ""
    for ($i = 0; $i -lt $Result.Path.Count; $i++) {
        $table = $Result.Path[$i]

        if ($i -eq 0) {
            $pathStr = "  [START: $table]"
        } elseif ($i -eq $Result.Path.Count - 1) {
            $edge = $Result.Edges[$i - 1]
            Write-Host $pathStr -ForegroundColor White -NoNewline
            Write-Host ""
            Write-Host ("  " + (" " * 4) + "| via $($edge.ColumnA) linked by {$($Result.Path[$i-1]).$($edge.ColumnA)} -> {$table.$($edge.ColumnB)}") -ForegroundColor DarkCyan
            Write-Host "  [END:   $table]" -ForegroundColor Green
        } else {
            $edge = $Result.Edges[$i - 1]
            Write-Host $pathStr -ForegroundColor White
            Write-Host ("  " + (" " * 4) + "| via $($edge.ColumnA) linked by {$($Result.Path[$i-1]).$($edge.ColumnA)} -> {$table.$($edge.ColumnB)}") -ForegroundColor DarkCyan
            $pathStr = "  [$table]"
        }
    }

    Write-Host ""

    # Show match type warnings
    $manualEdges = $Result.Edges | Where-Object { $_.Type -eq "manual" }
    if ($manualEdges) {
        Write-Host "  Note: $($manualEdges.Count) manually curated edge(s) in this path" -ForegroundColor Yellow
    }

    $mirrorEdges = $Result.Edges | Where-Object { $_.IsMirror }
    if ($mirrorEdges) {
        Write-Host "  Note: Path crosses x_/mi_ mirror boundary" -ForegroundColor Yellow
    }
}

# ── Shared Paginated Table List Renderer ─────────────────────

$PAGE_SIZE = 20

function Show-TablePage {
    param(
        [string[]]$Items,
        [int]$Page,
        [int]$PageSize,
        [string]$Filter,
        [string[]]$Selected,
        [string]$Mode
    )

    $totalPages = [Math]::Max(1, [Math]::Ceiling($Items.Count / $PageSize))
    $page       = [Math]::Max(0, [Math]::Min($Page, $totalPages - 1))
    $start      = $page * $PageSize
    $end        = [Math]::Min($start + $PageSize, $Items.Count) - 1

    if ($Items.Count -eq 0) {
        $filterStr = if ($Filter) { "  Filter: '$Filter'  " } else { "  " }
        Write-Host "${filterStr}No tables match." -ForegroundColor Red
        Write-Host ""
        return $page
    }

    $pageItems  = $Items[$start..$end]

    $filterStr = if ($Filter) { "  Filter: '$Filter'   " } else { "  " }
    $pageStr   = "Page $($page+1) of $totalPages  ($($Items.Count) tables)"
    Write-Host "$filterStr$pageStr" -ForegroundColor Yellow
    Write-Host ""

    $colWidth = 40
    $cols     = 2
    for ($i = 0; $i -lt $pageItems.Count; $i++) {
        $globalNum = $start + $i + 1
        $num   = "[$globalNum]".PadLeft(6)
        $name  = $pageItems[$i]
        $entry = "$num $name".PadRight($colWidth)
        $color = if ($Selected -and $name -in $Selected) { "Cyan" } else { "White" }
        if (($i + 1) % $cols -eq 0 -or $i -eq $pageItems.Count - 1) {
            Write-Host "  $entry" -ForegroundColor $color
        } else {
            Write-Host "  $entry" -ForegroundColor $color -NoNewline
        }
    }

    Write-Host ""

    $navParts = @()
    if ($page -gt 0)              { $navParts += "PREV" }
    if ($page -lt $totalPages-1)  { $navParts += "NEXT" }
    $navParts += "CLEAR"
    if ($Mode -eq "multi") { $navParts += "B = remove last   DONE = finish" }
    else                   { $navParts += "B = back" }

    Write-Host ("  Nav: " + ($navParts -join "   ")) -ForegroundColor DarkGray
    Write-Host ""

    return $page
}

# ── Single Table Selector (paginated) ────────────────────────

function Select-Table {
    param(
        [string[]]$Tables,
        [string]$Prompt
    )

    $filter   = ""
    $page     = 0
    $pageSize = $PAGE_SIZE

    while ($true) {
        Clear-Host

        $filtered = if ($filter) {
            @($Tables | Where-Object { $_ -like "*$filter*" })
        } else {
            @($Tables)
        }

        $totalPages = [Math]::Max(1, [Math]::Ceiling($filtered.Count / $pageSize))
        $page       = [Math]::Max(0, [Math]::Min($page, $totalPages - 1))

        Show-TablePage -Items $filtered -Page $page -PageSize $pageSize `
                       -Filter $filter -Mode "single" | Out-Null

        $inputRaw  = Read-Host "  $Prompt"
        $inputTrim = $inputRaw.Trim()

        if ($inputTrim -eq "")       { continue }
        if ($inputTrim -ieq "B")     { return "BACK" }
        if ($inputTrim -ieq "NEXT")  { $page = [Math]::Min($page + 1, $totalPages - 1); continue }
        if ($inputTrim -ieq "PREV")  { $page = [Math]::Max($page - 1, 0); continue }
        if ($inputTrim -ieq "CLEAR") { $filter = ""; $page = 0; continue }

        if ($inputTrim -match "^\d+$") {
            $globalIdx = [int]$inputTrim - 1
            if ($globalIdx -ge 0 -and $globalIdx -lt $filtered.Count) {
                return $filtered[$globalIdx]
            }
            Write-Host "  Invalid number." -ForegroundColor Red
            Start-Sleep -Milliseconds 600
            continue
        }

        $filter = $inputTrim
        $page   = 0
    }
}

# ── Multi-Table Selector (paginated + selected summary) ───────

function Select-MultipleTables {
    param([string[]]$Tables)

    $selected = [System.Collections.Generic.List[string]]::new()
    $filter   = ""
    $page     = 0
    $pageSize = $PAGE_SIZE

    while ($true) {
        Clear-Host
        Write-Header "MULTI-PATH: Select Tables to Connect"

        # Compact selected summary pinned below header
        if ($selected.Count -gt 0) {
            $summaryLine = "  Selected ($($selected.Count)/8): " + ($selected -join " -> ")
            if ($summaryLine.Length -gt 110) { $summaryLine = $summaryLine.Substring(0, 107) + "..." }
            Write-Host $summaryLine -ForegroundColor Cyan
        } else {
            Write-Host "  Selected (0/8): none yet" -ForegroundColor DarkGray
        }
        Write-Host ""
        Write-Host "  Min 2, max 8 tables. Numbers are global across pages." -ForegroundColor DarkGray
        Write-Host ""

        $available = @($Tables | Where-Object { $_ -notin $selected })
        $filtered  = if ($filter) {
            @($available | Where-Object { $_ -like "*$filter*" })
        } else {
            @($available)
        }

        $totalPages = [Math]::Max(1, [Math]::Ceiling($filtered.Count / $pageSize))
        $page       = [Math]::Max(0, [Math]::Min($page, $totalPages - 1))

        Show-TablePage -Items $filtered -Page $page -PageSize $pageSize `
                       -Filter $filter -Selected $selected -Mode "multi" | Out-Null

        $inputRaw  = Read-Host "  Number, filter, NEXT, PREV, CLEAR, B, or DONE"
        $inputTrim = $inputRaw.Trim()

        if ($inputTrim -eq "")       { continue }
        if ($inputTrim -ieq "NEXT")  { $page = [Math]::Min($page + 1, $totalPages - 1); continue }
        if ($inputTrim -ieq "PREV")  { $page = [Math]::Max($page - 1, 0); continue }
        if ($inputTrim -ieq "CLEAR") { $filter = ""; $page = 0; continue }

        if ($inputTrim -ieq "DONE") {
            if ($selected.Count -lt 2) {
                Write-Host "  Select at least 2 tables first." -ForegroundColor Red
                Start-Sleep -Seconds 1
            } else { break }
            continue
        }

        if ($inputTrim -ieq "B") {
            if ($selected.Count -gt 0) {
                $removed = $selected[$selected.Count - 1]
                $selected.RemoveAt($selected.Count - 1)
                Write-Host "  Removed: $removed" -ForegroundColor Yellow
                Start-Sleep -Milliseconds 500
            } else { return $null }
            continue
        }

        if ($inputTrim -match "^\d+$") {
            $globalIdx = [int]$inputTrim - 1
            if ($globalIdx -ge 0 -and $globalIdx -lt $filtered.Count) {
                $selected.Add($filtered[$globalIdx])
                $filter = ""
                $page   = 0
                if ($selected.Count -ge 8) {
                    Write-Host "  Maximum 8 tables reached." -ForegroundColor Yellow
                    Start-Sleep -Seconds 1
                    break
                }
            } else {
                Write-Host "  Invalid number." -ForegroundColor Red
                Start-Sleep -Milliseconds 600
            }
            continue
        }

        $filter = $inputTrim
        $page   = 0
    }

    return $selected.ToArray()
}

# ── Multi-Table: Build Pairwise Cost Matrix ──────────────────

function Build-CostMatrix {
    param($Graph, [string[]]$Tables)
    # Returns hashtable: "TableA||TableB" -> result object from Find-ShortestPath
    $matrix = @{}
    for ($i = 0; $i -lt $Tables.Count; $i++) {
        for ($j = $i + 1; $j -lt $Tables.Count; $j++) {
            $a = $Tables[$i]
            $b = $Tables[$j]
            $key = "$a||$b"
            $result = Find-ShortestPath -Graph $Graph -Start $a -End $b
            $matrix[$key] = $result
            $matrix["$b||$a"] = $result  # symmetric
        }
    }
    return $matrix
}

function Get-PairCost {
    param($Matrix, [string]$A, [string]$B)
    if ($A -eq $B) { return 0 }
    $key = "$A||$B"
    if (-not $Matrix.ContainsKey($key)) { return 999 }
    if (-not $Matrix[$key].Found) { return 999 }
    return $Matrix[$key].Path.Count - 1
}

# ── Multi-Table: Nearest Neighbour Tour ──────────────────────

function Find-MultiPath {
    param($Graph, [string[]]$TargetTables)

    # Step 1: build pairwise BFS between all targets
    $matrix    = Build-CostMatrix -Graph $Graph -Tables $TargetTables
    $reachable = [System.Collections.Generic.List[string]]::new()
    $isolated  = [System.Collections.Generic.List[string]]::new()

    # Determine which targets can reach at least one other target
    foreach ($t in $TargetTables) {
        $canReach = $false
        foreach ($other in $TargetTables) {
            if ($other -eq $t) { continue }
            if ((Get-PairCost -Matrix $matrix -A $t -B $other) -lt 999) {
                $canReach = $true; break
            }
        }
        if ($canReach) { $reachable.Add($t) } else { $isolated.Add($t) }
    }

    if ($reachable.Count -lt 2) {
        return @{
            Segments  = @()
            Isolated  = $isolated
            Reachable = $reachable
            Success   = $false
            Reason    = "Not enough connected tables to form a path"
        }
    }

    # Step 2: nearest-neighbour greedy tour starting from first reachable table
    $unvisited = [System.Collections.Generic.List[string]]::new($reachable)
    $tour      = [System.Collections.Generic.List[string]]::new()
    $tour.Add($unvisited[0])
    $unvisited.RemoveAt(0)

    while ($unvisited.Count -gt 0) {
        $current = $tour[$tour.Count - 1]
        $bestCost  = 999
        $bestTable = $null

        foreach ($candidate in $unvisited) {
            $cost = Get-PairCost -Matrix $matrix -A $current -B $candidate
            if ($cost -lt $bestCost) {
                $bestCost  = $cost
                $bestTable = $candidate
            }
        }

        if ($null -eq $bestTable) { break }  # remaining are unreachable from here
        $tour.Add($bestTable)
        $unvisited.Remove($bestTable)
    }

    # Step 3: stitch segments together, deduplicating bridge tables
    $segments     = [System.Collections.Generic.List[object]]::new()
    $fullPath     = [System.Collections.Generic.List[string]]::new()
    $targetSet    = @{}
    foreach ($t in $TargetTables) { $targetSet[$t] = $true }

    for ($i = 0; $i -lt $tour.Count - 1; $i++) {
        $from   = $tour[$i]
        $to     = $tour[$i + 1]
        $key    = "$from||$to"
        $result = $matrix[$key]

        $segments.Add([PSCustomObject]@{
            From   = $from
            To     = $to
            Result = $result
        })

        # Add to full path, skipping duplicate tables already in path
        foreach ($node in $result.Path) {
            if ($fullPath.Count -eq 0 -or $fullPath[$fullPath.Count - 1] -ne $node) {
                $fullPath.Add($node)
            }
        }
    }

    return @{
        Segments   = $segments
        FullPath   = $fullPath
        TargetSet  = $targetSet
        Isolated   = $isolated
        Reachable  = $reachable
        Tour       = $tour
        Success    = $true
    }
}

# ── Multi-Table: Display Result ──────────────────────────────

function Show-MultiPath {
    param($MultiResult, [string[]]$TargetTables)

    Write-Host ""

    # Show isolated tables first
    if ($MultiResult.Isolated.Count -gt 0) {
        Write-Host "  UNREACHABLE TABLES (no edges connect these):" -ForegroundColor Red
        foreach ($t in $MultiResult.Isolated) {
            Write-Host "    [!!] $t" -ForegroundColor Red
        }
        Write-Host "  Consider adding manual edges in edges.json for these." -ForegroundColor Yellow
        Write-Host ""
    }

    if (-not $MultiResult.Success) {
        Write-Host "  $($MultiResult.Reason)" -ForegroundColor Red
        return
    }

    $totalHops = ($MultiResult.FullPath.Count - 1)
    Write-Host "  Connected $($MultiResult.Reachable.Count) of $($TargetTables.Count) tables   Total hops: $totalHops" -ForegroundColor Green
    Write-Host ""

    # Display each segment
    foreach ($seg in $MultiResult.Segments) {
        $r = $seg.Result
        if (-not $r.Found) { continue }

        for ($i = 0; $i -lt $r.Path.Count; $i++) {
            $table     = $r.Path[$i]
            $isTarget  = $MultiResult.TargetSet.ContainsKey($table)
            $isBridge  = -not $isTarget

            $isFirst   = ($i -eq 0)
            $isLast    = ($i -eq $r.Path.Count - 1)

            # Label
            if ($isFirst -and $table -eq $MultiResult.Tour[0]) {
                $label = "[START: $table]"
                $color = "Green"
            } elseif ($isLast) {
                $label = "[TARGET: $table]"
                $color = "Cyan"
            } elseif ($isBridge) {
                $label = "(bridge: $table)"
                $color = "DarkYellow"
            } else {
                $label = "[TARGET: $table]"
                $color = "Cyan"
            }

            # Only print table if it's the first in the segment or not already shown
            if ($i -eq 0 -and $seg -ne $MultiResult.Segments[0]) {
                # Skip reprinting — already shown as last node of previous segment
            } else {
                Write-Host "  $label" -ForegroundColor $color
            }

            # Print the edge connector below this node (except last)
            if ($i -lt $r.Path.Count - 1) {
                $edge = $r.Edges[$i]
                $nextTable = $r.Path[$i + 1]
                $typeTag = if ($edge.Type -eq "manual") { " [manual]" } else { "" }
                Write-Host ("      | {$table.$($edge.ColumnA)} --> {$nextTable.$($edge.ColumnB)}$typeTag") -ForegroundColor DarkCyan
            }
        }
    }

    Write-Host ""

    # Summary of all connections
    Write-Section "Connection Summary"
    Write-Host ("  " + "FROM TABLE".PadRight(30) + "JOIN COLUMN".PadRight(25) + "TO TABLE") -ForegroundColor DarkGray
    Write-Host ("  " + ("-" * 75)) -ForegroundColor DarkGray

    foreach ($seg in $MultiResult.Segments) {
        $r = $seg.Result
        if (-not $r.Found) { continue }
        for ($i = 0; $i -lt $r.Edges.Count; $i++) {
            $edge      = $r.Edges[$i]
            $fromTable = $r.Path[$i]
            $toTable   = $r.Path[$i + 1]
            $joinStr   = "$($edge.ColumnA) = $($edge.ColumnB)"
            Write-Host ("  " + $fromTable.PadRight(30) + $joinStr.PadRight(25) + $toTable) -ForegroundColor White
        }
    }
}

# ── Search Mode ──────────────────────────────────────────────

function Invoke-SearchMode {
    param($Graph, $AllTables)

    Write-Header "SEARCH"
    Write-Host "  [1]  Point-to-point  - Connect two tables" -ForegroundColor White
    Write-Host "  [2]  Multi-path      - Connect multiple tables in one chain" -ForegroundColor White
    Write-Host "  [B]  Back" -ForegroundColor White
    Write-Host ""
    $choice = Read-Host "  Select option"

    switch ($choice.ToUpper()) {
        "1" { Invoke-PointSearch -Graph $Graph -AllTables $AllTables }
        "2" { Invoke-MultiSearch -Graph $Graph -AllTables $AllTables }
        "B" { return }
        default { return }
    }
}

function Invoke-PointSearch {
    param($Graph, $AllTables)

    Write-Header "SEARCH: Point-to-Point"

    Write-Section "Select Starting Table"
    $startTable = Select-Table -Tables $AllTables -Prompt "Select start table"
    if ($null -eq $startTable -or $startTable -eq "BACK") { return }

    Write-Header "SEARCH: Point-to-Point"
    Write-Host "  START: $startTable" -ForegroundColor Green
    Write-Section "Select Destination Table"

    $destTable = Select-Table -Tables $AllTables -Prompt "Select destination table"
    if ($null -eq $destTable -or $destTable -eq "BACK") { return }

    Write-Header "SEARCH: Point-to-Point"
    Write-Host "  START:  $startTable" -ForegroundColor Green
    Write-Host "  END:    $destTable" -ForegroundColor Cyan
    Write-Section "Computing..."

    $result = Find-ShortestPath -Graph $Graph -Start $startTable -End $destTable
    Show-Path -Result $result -Start $startTable -End $destTable

    Pause-ForKey
}

function Invoke-MultiSearch {
    param($Graph, $AllTables)

    $targets = Select-MultipleTables -Tables $AllTables
    if ($null -eq $targets -or $targets.Count -lt 2) { return }

    Clear-Host
    Write-Header "SEARCH: Multi-Path"
    Write-Host "  Tables to connect:" -ForegroundColor Yellow
    foreach ($t in $targets) { Write-Host "    - $t" -ForegroundColor Cyan }
    Write-Section "Computing optimal path..."

    $result = Find-MultiPath -Graph $Graph -TargetTables $targets
    Show-MultiPath -MultiResult $result -TargetTables $targets

    Pause-ForKey
}

# ── Visualise Mode ───────────────────────────────────────────

function Invoke-VisualiseMode {
    param($Graph, $Schema, $AllTables)

    Write-Header "VISUALISE: Table Connections"

    $table = Select-Table -Tables $AllTables -Prompt "Select table to inspect"
    if ($null -eq $table -or $table -eq "BACK") { return }

    Write-Header "VISUALISE: $table"

    # Show columns for this table
    $tableData = $Schema.tables.$table
    if ($tableData) {
        Write-Section "Columns in $table"
        Write-Host ("  " + "COLUMN NAME".PadRight(35) + "TYPE".PadRight(20) + "NULLABLE") -ForegroundColor DarkGray
        Write-Host ("  " + ("-" * 65)) -ForegroundColor DarkGray
        foreach ($col in $tableData.columns) {
            $type     = if ($col.data_type) { $col.data_type } else { "" }
            $nullable = if ($col.is_nullable) { $col.is_nullable } else { "" }
            Write-TableRow -Col1 $col.name -Col2 $type -Col3 $nullable
        }
    }

    # Show connections grouped by column
    if ($Graph.ContainsKey($table)) {
        Write-Section "Connections from $table"
        Write-Host ("  " + "THIS COLUMN".PadRight(30) + "CONNECTS TO TABLE".PadRight(35) + "VIA COLUMN") -ForegroundColor DarkGray
        Write-Host ("  " + ("-" * 80)) -ForegroundColor DarkGray

        $connections = $Graph[$table] | Sort-Object ColumnA, Table
        foreach ($conn in $connections) {
            $typeTag  = if ($conn.Type -eq "manual") { " [M]" } else { "" }
            $mirrorTag = if ($conn.IsMirror) { " [mirror]" } else { "" }
            $colDisplay = "$($conn.ColumnA)$typeTag$mirrorTag"
            Write-Host ("  " + $colDisplay.PadRight(30) + $conn.Table.PadRight(35) + $conn.ColumnB) -ForegroundColor White
        }

        Write-Host ""
        Write-Host "  [M] = manually curated edge    [mirror] = x_/mi_ pair" -ForegroundColor DarkGray
        Write-Host "  Total connections: $($connections.Count)" -ForegroundColor DarkGray

    } else {
        Write-Host "  No connections found for this table." -ForegroundColor Yellow
        Write-Host "  This table may be isolated - consider adding manual edges." -ForegroundColor DarkGray
    }

    Pause-ForKey
}

# ── Main Menu ────────────────────────────────────────────────

function Show-MainMenu {
    param([bool]$IncludeMirror, [int]$EdgeCount, [int]$TableCount)

    Write-Header "MIS DATABASE SCHEMA GRAPH TOOL"
    Write-Host "  Tables loaded : $TableCount" -ForegroundColor Gray
    Write-Host "  Edges loaded  : $EdgeCount" -ForegroundColor Gray
    Write-Host "  Mirror edges  : $(if ($IncludeMirror) { 'INCLUDED (x_/mi_ shown)' } else { 'HIDDEN (x_/mi_ filtered)' })" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [1]  Search     - Point-to-point or multi-table path" -ForegroundColor White
    Write-Host "  [2]  Visualise  - Inspect a table and its connections" -ForegroundColor White
    Write-Host "  [3]  Toggle     - $(if ($IncludeMirror) { 'Hide' } else { 'Show' }) x_/mi_ mirror edges" -ForegroundColor White
    Write-Host "  [Q]  Quit" -ForegroundColor White
    Write-Host ""
    return Read-Host "  Select option"
}

# ── Entry Point ──────────────────────────────────────────────

Clear-Host

# Load files
$schema  = Load-JsonFile -Path $SchemaPath -Name "schema.json"
$edges   = Load-JsonFile -Path $EdgesPath  -Name "edges.json"
$config  = Load-JsonFile -Path $ConfigPath -Name "config.json"

# Settings
$includeMirror = if ($null -ne $config.include_mirror_edges) { [bool]$config.include_mirror_edges } else { $true }

# Get sorted table list
$allTables = ($schema.tables.PSObject.Properties.Name) | Sort-Object

# Build initial graph
$graph = Build-Graph -Edges $edges -IncludeMirror $includeMirror
$edgeCount = $edges.edges.Count

# Main loop
while ($true) {
    Clear-Host
    $choice = Show-MainMenu -IncludeMirror $includeMirror -EdgeCount $edgeCount -TableCount $allTables.Count

    switch ($choice.ToUpper()) {
        "1" {
            Clear-Host
            Invoke-SearchMode -Graph $graph -AllTables $allTables
        }
        "2" {
            Clear-Host
            Invoke-VisualiseMode -Graph $graph -Schema $schema -AllTables $allTables
        }
        "3" {
            $includeMirror = -not $includeMirror
            $graph = Build-Graph -Edges $edges -IncludeMirror $includeMirror
        }
        "Q" {
            Write-Host ""
            Write-Host "  Goodbye." -ForegroundColor Cyan
            Write-Host ""
            exit
        }
        default {
            Write-Host "  Invalid option" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
