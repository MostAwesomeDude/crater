exports (formatByteSize, formatPercentage)

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
