import "lib/codec" =~ [=> composeCodec :DeepFrozen]
import "lib/codec/utf8" =~ [=> UTF8 :DeepFrozen]
import "lib/json" =~ [=> JSON :DeepFrozen]
import "lib/tubes" =~ [
    => makeUTF8EncodePump :DeepFrozen,
    => makePumpTube :DeepFrozen,
]
import "lib/gai" =~ [=> makeGAI :DeepFrozen]
import "http/client" =~ [=> makeRequest :DeepFrozen]
import "crater/stats" =~ [
    => makeStatistics :DeepFrozen,
]
exports (main)

def UTF8JSON :DeepFrozen := composeCodec(UTF8, JSON)

def undot(specimen) as DeepFrozen:
    "Recursively re-add structure by undoing dots."

    return switch (specimen):
        match m :Map:
            var newMap := [].asMap()
            for k => v in (m):
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

def setupPoller(hostname :Bytes, getAddrInfo, makeTCP4ClientEndpoint) as DeepFrozen:
    def addrs := getAddrInfo(hostname, b``)
    return when (addrs) ->
        traceln(`Finished GAI: $addrs`)
        def gai := makeGAI(addrs)
        def [addr] + _ := gai.TCP4()
        def address := addr.getAddress()
        def port :Int := 3456
        def poll():
            traceln(`Making HTTP request to $address:$port`)
            return makeRequest(makeTCP4ClientEndpoint, address,
                               "/statistics?t=json", => port).get()

def main(argv, => getAddrInfo, => makeTCP4ClientEndpoint, => makeStdOut) as DeepFrozen:
    def [via (UTF8.encode) hostname] := argv
    def stdout := setupStdOut(makeStdOut)
    def poll := setupPoller(hostname, getAddrInfo, makeTCP4ClientEndpoint)

    return when (def response := poll<-()) ->
        traceln(`Got response $response`)
        def via (UTF8JSON.decode) dottedMap := response.body()
        def undottedMap := undot(dottedMap)
        def name :Str := argv[0]
        def stats := makeStatistics(name, undottedMap)
        stdout<-receive(stats.report())
        stdout<-receive("\n")
        0
    catch problem:
        traceln.exception(problem)
        stdout<-receive(`Problem: $problem$\n`)
        1
