xquery version "3.0";

(:
 : This file is a try for porting MarkLogic and BaseX implementation of maps
 : 
 : Thibault Clérice
 : ponteineptique@github
 :)

module namespace ahab-rest = "http://github.com/capitains/ahab-rest";

import module namespace ahabx = "http://github.com/capitains/ahab/x" at "./ahab.xql";
declare namespace ahab ="http://github.com/Capitains/ahab";
declare namespace rest = "http://exquery.org/ns/restxq";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace util="http://exist-db.org/xquery/util";

declare variable $ahab-rest:debug := fn:doc("../conf/conf.xml")//debug;

declare
    %rest:GET
    %rest:path("/ahab")
    %rest:query-param("request", "{$request}", "")
    %rest:query-param("urn", "{$urn}", "")
    %rest:query-param("query", "{$query}", "")
    %rest:query-param("start", "{$start}", "1")
    %rest:query-param("limit", "{$limit}", "5")
    %rest:produces("application/xml", "text/xml")
function ahab-rest:root(
    $request as xs:string*,
    $urn as xs:string*,
    $query as xs:string*,
    $start as xs:string*,
    $limit as xs:string*
) {
    
    let $startTime := util:system-time()
    let $_start := xs:integer($start)
    let $_limit := xs:integer($limit)
    let $_request := ahab-rest:routerText($request)
    
    let $reply :=
        try {
          if ($_request = 'Search')
            then ahabx:search($urn, $query, $_start, $_limit)
          else if ($_request = 'Permalink')
            then ahabx:permalink($urn)
          else
            fn:error(
              xs:QName("INVALID-REQUEST"),
              "Unsupported request: " || $request
            )
        } catch * {
          ahab-rest:errorLayout($err:description, $err:value, $err:code, $err:line-number, $err:column-number, $err:additional)
        }
    
    return
      if (fn:node-name($reply) eq xs:QName("ahab:ahabError") or fn:empty($reply))
      then ahab-rest:debug($reply)
      else ahab-rest:http-okay($_request, $urn, $query, $_limit, $_start, $startTime, $reply)
}; 

declare %private 
function ahab-rest:errorLayout
(
    $description, 
    $value, 
    $code, 
    $line-number, 
    $column-number, 
    $additional
) {
    <ahab:ahabError>
      <message>{ $description }</message>
      <value>{ $value }</value>
      <code>{ $code }</code>
      <position>l {$line-number}, c {$column-number}</position>
      <stack>{$additional}</stack>
    </ahab:ahabError>
};

declare %private
    function 
    ahab-rest:routerText(
        $e_query as xs:string*
    ) as xs:string {
    switch(fn:lower-case($e_query))
        case "search" 
            return "Search" 
        case "permalink" 
            return "Permalink" 
        default
            return "" (: When the request does not exist :)
};

(:~ 
 :  Generates a HTTP response element with a payload.  
 :)
declare %private function ahab-rest:http-response($http-code as xs:integer, $resource)
{
    (
        <rest:response>
            <http:response status="{$http-code}">
            </http:response>
        </rest:response>,
        $resource
    )
};

declare %private function ahab-rest:debug($information as node()*) {
    let $code := 
        if ($information/code/text() eq "UNKNOWN-RESOURCE")
        then 409
        else 400
    return
      if($ahab-rest:debug/text() eq "yes")
      then ahab-rest:http-response($code, $information)
      else ahab-rest:http-response($code, <ahab:ahabError>{$information/code}</ahab:ahabError>)
  
};

declare %private 
function ahab-rest:http-okay(
    $e_request as xs:string,
    $e_urn as xs:string*,
    $e_query as xs:string*,
    $limit as xs:int*,
    $start as xs:int*,
    $startTime as xs:time,
    $reply as node()
) {
    ahab-rest:http-response(200, 
        element { "ahab:" || $e_request } {
          element ahab:request {
            attribute elapsed-time { string(seconds-from-duration(util:system-time() - $startTime) * 1000) },
            element ahab:requestName { $e_request },
            element ahab:requestUrn { $e_urn },
            element ahab:query { $e_query },
            element ahab:option {
                if ($e_request = "search")
                then (
                        element ahab:limit {
                            $limit
                        },
                        element ahab:start {
                            $start
                        }
                    )
                else ()
            }
          },
          $reply
        }
    ) 
};