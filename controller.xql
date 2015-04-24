xquery version "3.0";
(:
 : This file is a try for porting MarkLogic and BaseX implementation of maps
 : 
 : Thibault Clérice
 : ponteineptique@github
 :)

import module namespace mapsutils = "http://github.com/ponteineptique/CTS-API"
       at "modules/maps-utils.xq";
import module namespace ahabx = "http://github.com/capitains/ahab/x"
       at "modules/ahab.xq";
import module namespace ctsi = "http://alpheios.net/namespaces/cts-implementation"
       at "modules/cts-impl.xq";
import module namespace console = "http://exist-db.org/xquery/console";

declare namespace CTS = "http://chs.harvard.edu/xmlns/cts";
declare namespace ahab = "http://github.com/capitains/ahab";
declare namespace tei = "http://www.tei-c.org/ns/1.0";
declare namespace error = "http://marklogic.com/xdmp/error";

let $startTime := util:system-time()
let $map := map:new()
let $_ := ctsi:add-response-header("Access-Control-Allow-Origin", "*")

let $start := xs:integer(request:get-parameter("start", "1"))
let $limit := xs:integer(request:get-parameter("limit", "5"))

let $e_request := ctsi:get-request-parameter("request", ())
let $e_query := ctsi:get-request-parameter("query", ())
let $e_urn :=  ctsi:get-request-parameter("urn", ())
let $e_inv := ctsi:get-request-parameter("inv", "annotsrc")
let $query := fn:lower-case($e_request)

let $reply :=
try
{
  if ($query = 'search')
  then ahabx:search($e_urn, $e_query, $start, $limit)
  else if ($query = 'permalink')
  then ahabx:permalink($e_urn)
  else
    fn:error(
      xs:QName("INVALID-REQUEST"),
      "Unsupported request: " || $e_request
    )
} catch * {
  console:log($err:description || $err:code || $err:value),
  <ahab:ahabError>
    <message>{ $err:description }</message>
    <value>{ $err:value }</value>
    <code>{ $err:code }</code>
    <position>l {$err:line-number}, c {$err:column-number}</position>
    <stack>{$err:additional}</stack>
  </ahab:ahabError>
}

let $cts := map:get($map, "cts")
let $response :=
  if (fn:node-name($reply) eq xs:QName("ahab:ahabError"))
  then
    $reply
  else
    element { "ahab:" || $e_request }
    {
      element ahab:request
      {
        attribute elapsed-time { string(seconds-from-duration(util:system-time() - $startTime) * 1000) },
        element ahab:requestName { $e_request },
        element ahab:requestUrn { $e_urn },
        element ahab:query { $e_query },
        element ahab:option {
            if ($e_request = "search")
            then 
                (
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

return
  element { fn:name($response) }
  {
    $response/@*,
    $response/*
  }