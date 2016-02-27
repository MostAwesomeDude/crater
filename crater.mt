import "lib/codec" =~ [=> composeCodec :DeepFrozen]
import "lib/codec/utf8" =~ [=> UTF8 :DeepFrozen]
import "lib/json" =~ [=> JSON :DeepFrozen]
import "lib/tubes" =~ [
    => makeUTF8EncodePump :DeepFrozen,
    => makePumpTube :DeepFrozen,
]
exports (main)

def UTF8JSON :DeepFrozen := composeCodec(UTF8, JSON)

def prefixes :List[Str] := ["B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB"]
def formatByteSize(i :Int) :Str as DeepFrozen:
    "Pretty-print a number of bytes into a string."

    var d := i
    var prefixIndex :Int := 0
    while (d > 1024):
        d /= 1024
        prefixIndex += 1
    return `$d ${prefixes[prefixIndex]}`

def formatPercentage(portion, total) :Str as DeepFrozen:
    "Pretty-print a percentage."

    return `${portion * 100 / total}%`

def makeDiskStatistics(diskTotal :Int, diskUsed :Int, diskAvailable :Int) as DeepFrozen:
    return object diskStatistics as DeepFrozen:
        to report():
            return " ".join([
                `Total: ${formatByteSize(diskTotal)}`,
                `Used: ${formatByteSize(diskUsed)}`,
                `(${formatPercentage(diskUsed, diskTotal)})`,
                `Available: ${formatByteSize(diskAvailable)}`,
                `(${formatPercentage(diskAvailable, diskTotal)})`,
            ])

def makeStorageStatistics(data) as DeepFrozen:
    def [
        => accepting_immutable_shares :Int,
        "total_bucket_count" => bucketCount :Int,
        "disk_used" => diskUsed :Int,
        "disk_avail" => diskAvailable :Int,
        "disk_total" => diskTotal :Int,
    ] | rest := data
    traceln(`storage stats $rest`)

    def acceptingImmutableShares :Bool := accepting_immutable_shares != 0
    def disk :DeepFrozen := makeDiskStatistics(diskTotal, diskUsed,
                                               diskAvailable)

    return object storageStatistics as DeepFrozen:
        to report():
            return "\n".join([
                `Storage server with $bucketCount buckets`,
                `Accepting immutable shares: $acceptingImmutableShares`,
                `Disk: ${disk.report()}`,
            ])

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

def undot(specimen) as DeepFrozen:
    "Recursively re-add structure by undoing dots."

    return switch (specimen):
        match m :Map:
            var newMap := [].asMap()
            for k => v in m:
                if (k =~ `@head.@tail`):
                    def values := newMap.fetch(head, fn {[].asMap()})
                    newMap with= (head, values.with(tail, v))
                else:
                    newMap with= (k, v)
            # And recurse.
            [for k => v in (newMap) k => undot(v)]
        match l :List:
            [for x in (l) undot(x)]
        match _:
            specimen

def setupStdOut(makeStdOut) as DeepFrozen:
    def stdout := makePumpTube(makeUTF8EncodePump())
    stdout<-flowTo(makeStdOut())
    return stdout

def main(argv, => makeFileResource, => makeStdOut) as DeepFrozen:
    def stdout := setupStdOut(makeStdOut)

    def bs := makeFileResource(argv.last())<-getContents()
    return when (bs) ->
        def via (UTF8JSON.decode) dottedMap := bs
        def undottedMap := undot(dottedMap)
        for name => data in undottedMap:
            def stats := makeStatistics(name, data)
            stdout<-receive(stats.report())
            stdout<-receive("\n")
        0
