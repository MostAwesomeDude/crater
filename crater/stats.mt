import "crater/formatting" =~ [
    => formatByteSize :DeepFrozen,
    => formatPercentage :DeepFrozen,
]
exports (makeStatistics)

def makeDiskStatistics(diskTotal :Int, diskUsed :Int, diskAvailable :Int) as DeepFrozen:
    return object diskStatistics as DeepFrozen:
        to report() :Str:
            return " ".join([
                `Total: ${formatByteSize(diskTotal)}`,
                `Used: ${formatByteSize(diskUsed)}`,
                `(${formatPercentage(diskUsed, diskTotal)})`,
                `Available: ${formatByteSize(diskAvailable)}`,
                `(${formatPercentage(diskAvailable, diskTotal)})`,
            ])

def makeSampledStatistics(name :Str, data) as DeepFrozen:
    def [
        "samplesize" => sampleSize :Int,
        => mean :NullOk[Double],
    ] | rawPercentiles := data

    def percentiles :Map[Str, NullOk[Double]] := {
        def m := [].asMap().diverge()
        for `@{cent}_@{tenth}_percentile` => value in (rawPercentiles) {
            if (value != null) {
                m[`$cent.$tenth`] := value
            }
        }
        m.snapshot().sortKeys()
    }

    return object sampledStatistics as DeepFrozen:
        to report() :Str:
            def info := if (mean != null) {
                def l := [for label => value in (percentiles) `$label%: $value`]
                ", ".join(l + [`Mean: $mean`])
            } else {"Insufficient data"}
            return `$name: $info ($sampleSize samples)`

def makeStorageStatistics(data) as DeepFrozen:
    # We don't match everything. There's a couple more stats that aren't
    # currently interesting; we drop them on the floor.
    def [
        => accepting_immutable_shares :Int,
        "total_bucket_count" => bucketCount :Int,
        "disk_used" => diskUsed :Int,
        "disk_avail" => diskAvailable :Int,
        "disk_total" => diskTotal :Int,
        "latencies" => rawLatencies := [].asMap(),
    ] | _ := data

    def acceptingImmutableShares :Bool := accepting_immutable_shares != 0
    def disk :DeepFrozen := makeDiskStatistics(diskTotal, diskUsed,
                                               diskAvailable)
    # Nor this one.
    def latencies :List[DeepFrozen] := [for k => v in (rawLatencies.sortKeys()) makeSampledStatistics(k, v)]

    return object storageStatistics as DeepFrozen:
        to report():
            return "\n".join([
                `Storage server with $bucketCount buckets`,
                `Accepting immutable shares: $acceptingImmutableShares`,
                `Disk: ${disk.report()}`,
            ] + [for v in (latencies) v.report()])

def makeStatistics(name :Str, data) as DeepFrozen:
    def [
        => nickname :Str,
        => timestamp :Double,
        "stats" => [
            "counters" => counters,
            "stats" => [
                "storage_server" => storageServerStats,
            ] | _,
        ],
    ] := data

    # `stats` also contains this key on helpers.
    def hasHelper :Bool := counters.contains("chk_upload_helper")

    # Process storage server statistics.
    def storageServer :DeepFrozen := makeStorageStatistics(storageServerStats)

    return object statistics as DeepFrozen:
        to report():
            return "\n".join([
                `$nickname ($name) checked at $timestamp:`,
                `Helper: ${hasHelper.pick("enabled", "disabled")}`,
                storageServer.report(),
                `…`,
            ])
