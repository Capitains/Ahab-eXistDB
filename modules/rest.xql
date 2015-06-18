xquery version "3.0";

(:
 : This file is a try for porting MarkLogic and BaseX implementation of maps
 : 
 : Thibault Clérice
 : ponteineptique@github
 :)

import module namespace ahabx = "http://github.com/capitains/ahab/x"
       at "./ahab.xq";

declare namespace ahab-rest = "http://github.com/capitains/ahab-rest";
declare namespace ahab ="http://github.com/Capitais/ahab";
declare namespace rest = "http://exquery.org/ns/restxq";

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
    $e_request as xs:string*,
    $e_urn as xs:string*,
    $e_query as xs:string*,
    $e_start as xs:string*,
    $e_limit as xs:string*
) {
    
    let $startTime := util:system-time()
    let $start := xs:integer($e_start)
    let $limit := xs:integer($e_limit)
    let $request := ahab-rest:routerText($e_request)
    
    let $reply :=
        try {
          if ($query = 'Search')
            then ahabx:search($e_urn, $e_query, $start, $limit)
          else if ($query = 'Permalink')
            then ahabx:permalink($e_urn)
          else
            fn:error(
              xs:QName("INVALID-REQUEST"),
              "Unsupported request: " || $e_request
            )
        } catch * {
          ahab-rest:errorLayout($err:description, $err:value, $err:code, $err:line-number, $err:column-number, $err:additional)
        }
    
    return
      if (fn:node-name($reply) eq xs:QName("ahab:ahabError"))
      then
        ahab-rest:debug($reply)
      else
        ahab-rest:http200($e_request, $e_urn, $e_query, $limit, $start, $startTime, $reply)
}; 

declare %private function ahab-rest:errorLayout
    ($description, $value, $code, $line-number, $column-number, $additional) {
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
  if($ahab-rest:debug/text() eq "yes")
  then ahab-rest:http-response(400, $information)
  else ahab-rest:http-response(400, <CTS:CTSError>{$information/code}</CTS:CTSError>)
  
};

declare %private 
function ahab-rest:http200(
    $e_request as xs:string,
    $e_urn as xs:string*,
    $e_query as xs:string*,
    $limit as xs:int*,
    $start as xs:int*,
    $startTime as xs:int,
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