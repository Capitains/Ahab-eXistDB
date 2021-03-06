xquery version "3.0";

(:
 : This file is a try for porting MarkLogic and BaseX implementation of maps
 : 
 : Thibault Clérice
 : ponteineptique@github
 :)

module namespace ahabx = "http://github.com/capitains/ahab/x";

import module namespace kwic="http://exist-db.org/xquery/kwic";
declare namespace ahab ="http://github.com/Capitains/ahab";
declare namespace ti = "http://chs.harvard.edu/xmlns/cts";
declare namespace util="http://exist-db.org/xquery/util";
declare namespace ft="http://exist-db.org/xquery/lucene";
declare namespace tei="http://www.tei-c.org/ns/1.0";

declare variable $ahabx:conf := fn:doc("../conf/conf.xml");
declare variable $ahabx:inventories := collection($ahabx:conf//repositories/@inventoryCollection/text());

(: 
 : Get the xpath of the smallest node for a given text record.
:)
declare function ahabx:citationXpath($citation) {
    
    let $first := fn:string($citation/@scope)
    let $last := replace(fn:string($citation/@xpath), "//", "/")
    
    let $scope := fn:concat($first, $last)
    let $xpath := replace(replace($scope,"='\?'",''), "^(.*)body/", "")
    return $xpath
};
(: 
 :)
declare function ahabx:collectionFromUrn($a_urn) {
    for $item in $ahabx:inventories//ti:edition[fn:starts-with(@urn, $a_urn)]//ti:online/@docname
    return fn:doc(
        fn:string($item)
    )
};

(: 
 : $a_urn Urn or namespace
 : $a_query Query
 :)

declare function local:filter($node as node(), $mode as xs:string) as xs:string? {
        if ($node/name(.) = ("tei:note", "note")) then
            ()
        else
            concat(" ",
                $node[not(./ancestor::tei:note)]
                , " ")
};

declare %private function local:parentUrns($node) {
    let $ns := $node/ancestor::master-level
    return
        (for $n in $ns
            return xs:string($n/@n))
};


declare function ahabx:search($a_urn, $a_query, $a_start, $a_limit)
{
    let $_ :=
        if(fn:empty($a_urn))
        then 
            fn:error(
              xs:QName("MISSING-PARAMETER"),
              "Missing parameter 'urn' "
            )
        else if (fn:empty($a_query))
        then 
            fn:error(
              xs:QName("MISSING-PARAMETER"),
              "Missing parameter 'query' "
            )
        else if (fn:empty($a_start))
        then 
            fn:error(
              xs:QName("WRONG-PARAMETER-VALUE"),
              "Wrong parameter value for 'limit' "
            )
        else if (fn:empty($a_limit))
        then 
            fn:error(
              xs:QName("WRONG-PARAMETER-VALUE"),
              "Wrong parameter value for 'limit' "
            )
        else ()
    let $collection_from_urn := ahabx:collectionFromUrn($a_urn)
    let $__ := 
        if(fn:empty($collection_from_urn))
        then fn:error(
              xs:QName("UNKNOWN-RESOURCE"),
              "Wrong parameter value for 'urn' : no resource available for this information "
        )
        else ()
    let $config := <config xmlns="" width="200"/>
    let $hits := $collection_from_urn//tei:body[ft:query(., $a_query)]
    
    let $matches := for $hit in $hits return kwic:expand($hit)
    let $hitCount :=  count($matches//exist:match)
    
    let $results := 
    for $hit in $hits
        let $path := fn:concat(util:collection-name($hit), "/", util:document-name($hit))
        let $docname := $ahabx:inventories//ti:online[@docname=$path][1]
        let $editionNode := $docname/..
        
        let $urn := if ($editionNode/@urn)
            then fn:string($editionNode/@urn)
        else
            let $edition := tokenize($docname/../@projid, ":")[2]
            let $work := tokenize($docname/../../@projid, ":")[2]
            let $textgroup := tokenize($docname/../../../@projid, ":")[2]
            
            return concat("urn:cts:",$textgroup,".",$work,".",$edition)
            
        let $body := kwic:expand($hit)
        
        let $citations := ($editionNode//ti:citation)
        let $urns := local:fake-match-document($citations, $body, (), $urn)
        let $matches := $urns//exist:match
        return
            for $match in $matches
                let $passage_urn := $urn || ":" || string-join(local:parentUrns($match), ".")
                return 
                    element ahab:result {
                        element ahab:urn { $urn },
                        element ahab:passageUrn { $passage_urn },
                        element ahab:text {
                            kwic:get-summary($match/ancestor::master-level[@level="1"], $match, $config, util:function(xs:QName("local:filter"), 2))
                        }
                    }
        
    return 
        element ahab:reply {
            element ahab:query   { $a_query },
            element ahab:urn     { $a_urn },
            element ahab:results { 
                attribute ahab:offset { $a_start },
                attribute ahab:limit { $a_limit },
                attribute ahab:count { $hitCount },
                $results
            }
        }
};

declare %private function local:fake-match-document($citations as element()*, $body as element()*, $remove as xs:string?, $urn as xs:string) {
    let $citation := $citations[1]
    let $xpath := ahabx:citationXpath($citation)
    let $masterPath := 
        if ($remove)
        then replace($xpath, "^("||replace($remove, '(\.|\[|\]|\\|\||\-|\^|\$|\?|\*|\+|\{|\}|\(|\))','\\$1')||")", "")
        else $xpath
    let $efficientXpath := replace($masterPath, "(\[[a-zA-Z1-9=@]+\]*)$", "[.//exist:match]$1")
    let $masters := util:eval("$body/" || $efficientXpath)
    let $next := subsequence($citations, 2)
    
    return 
            for $master in $masters 
             let $childs := 
                if( count($next) = 0)
                then
                    $master/child::node()
                else
                    local:fake-match-document($next, $master, $xpath, $urn)
                    
             return element master-level {
                attribute level { count($citations) },
                $master/@n,
                $childs
         }
    (:
    :)
};

(: 
 : $a_urn Urn or namespace
 : $a_query Query
 :)
declare function ahabx:permalink($a_urn)
{
    let $_ :=
        if(fn:empty($a_urn))
        then 
            fn:error(
              xs:QName("MISSING-PARAMETER"),
              "Missing parameter 'urn' "
            )
        else ()
    let $parsed_urn := ahabx:simpleUrnParser($a_urn)
    let $inv := ($ahabx:inventories//ti:TextInventory[count(.//ti:work[@urn eq $parsed_urn/workUrn/text()]/ti:edition) = 1])[1]
    let $_ :=
        if(fn:empty($inv))
        then 
            fn:error(
              xs:QName("UNKOWN-RESOURCE"),
              "Wrong parameter value for 'urn' : no resource available for this information "
            )
        else ()
    let $work := $inv//ti:work[@urn eq $parsed_urn/workUrn/text()]
    
    let $urn := 
        if (fn:empty($parsed_urn/version/text()))
        then fn:string($work//ti:edition[1]/@urn)
        else fn:string($parsed_urn/version/text())
        
    let $urn_passage :=
        if (fn:empty($parsed_urn/passage/text()))
        then $urn
        else $urn || ":" || fn:string($parsed_urn/passage/text())
        
    let $request :=
        if (fn:empty($parsed_urn/passage/text()))
        then "GetValidReff"
        else "GetPassagePlus"
        
    return element ahab:reply {
        element ahab:urn { $urn_passage },
        element ahab:request { fn:string($request) },
        element ahab:inventory { fn:string($inv/@tiid) }
    }
};

declare function ahabx:simpleUrnParser($a_urn)
{
    let $components := fn:tokenize($a_urn, ":")
    let $workComponents := fn:tokenize($components[4], "\.")
    let $textgroup := $workComponents[1]
    let $work := $workComponents[2]

    let $passage := $components[5]
    
    let $namespaceUrn := fn:string-join($components[1,2,3], ":")
    let $groupUrn := if (fn:exists($textgroup)) then $namespaceUrn || ":" || $textgroup else ()
    let $workUrn := if(fn:exists($work)) then $groupUrn || "." || $work else ()
    let $version := if(fn:exists($workComponents[3])) then $workUrn || "." || $workComponents[3] else ()
    
    
    return
      element reply
      {
        element urn { $a_urn },
        (: urn without any passage specifics:)
        element groupUrn { $groupUrn },
        element workUrn { $workUrn },
        element namespace{ $namespaceUrn },
        element version { $version },
        element passage { $passage }
      }
};
