import "lib/codec" =~ [=> composeCodec :DeepFrozen]
import "lib/codec/utf8" =~ [=> UTF8 :DeepFrozen]
import "lib/json" =~ [=> JSON :DeepFrozen]
exports (main)

def UTF8JSON :DeepFrozen := composeCodec(UTF8, JSON)

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

def main(argv, => makeFileResource) as DeepFrozen:
    def bs := makeFileResource(argv.last())<-getContents()
    return when (bs) ->
        def via (UTF8JSON.decode) dottedMap := bs
        def undottedMap := undot(dottedMap)
        traceln(undottedMap)
        0
