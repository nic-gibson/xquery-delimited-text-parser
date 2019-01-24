xquery version "1.0-ml";

(:~
MIT License

Copyright (c) 2017-2019 Nic Gibson

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
:)

(:~
    OPTIONS
    The following options are available to users. Any other options may be added
    as long as the do not start with an exclamation mark (this is used for 
    internal options). 

    field-delimiter
        Set the field delimiter. This must be a literal string (it is not used
        as a regular expression). The default is a single comma.
    record-delimiter
        Set the record delimiter. This may be a regular expression as it is used
        as a paramter to fn:tokenize
    quote
        The quote character used on quoted fields
    quote-escape
        This character is used to replace doubled quotes within fields
        (e.g. abc,d "quoted" e, fgh ). Only replace it if the input data may 
        contain '!!!q!!!'.
    record-element
        The name of an element to be used to wrap a single record on output
        (see the post-parse function below)
    field-element
        The name of an element to be used to wrap a single field out output
        (see the post-parse function below)
    line-filter
        This is a function which receives two parameters - a line of text and
        the options map. The function can modify the input before it is parsed
        into fields. If the filter returns an empty sequence the line will be
        skipped. The default function returns the string unchanged.
    field-filter
        This is a function which can be used to modify a field after parsing.
        It is provided with two parameters - the string and the options map.
        The default function returns the field unchanged. If an empty sequence
        is returned the field will have no value. 
    internal-quote-escape
        This function is used to escape any doubled quotes with the value of
        quote-escape. There is probably no need to override this function but
        if overriden it should take two parameters as below and return the
        string 
    internal-quote-unescape
        The opposite of the above function, returning a string with internal
        doubled quotes replaced with a single quote. This is called after
        a line has been processed into fields, once for each field. 
    post-parse
        This function is called immediately after the parsing process. The default
        version of this function creates an element using the value of the 'record-element'
        configuration value and child elements in sequence using the value of the 
        'field-element' value. All elements are in no namespace. The parameters are the
        sequence of fields as strings and the options
    report-error
        This function should be overridden if any error reporting that does not
        terminate processing is required. The default funtion calls fn:error .
        A replacement should take for parameters - the invalid line, the line
        number, an error message and the options map.
:)

declare variable $DEFAULT-OPTIONS := map:new()
    => map:with('record-delimiter', ',')
    => map:with('field-delimiter', ',')
    => map:with('quote', '&quot;')
    => map:with('quote-escape',  '!!!q!!!')
    => map:with('record-element', 'record')
    => map:with('field-element', 'field')
    => map:with('line-filter', function($line as xs:string, $options as map:map) as xs:string? {$line})
    => map:with('field-filter', function($field as xs:string, $options as map:map) as xs:string {$field})
    => map:with('internal-quote-escape',
        function($line as xs:string, $options as map:map) as xs:string {
            replace($line, 
              map:get($options, 'quote') || map:get($options, 'quote'), 
              map:get($options, 'quote-escape'))
        })
    => map:with('internal-quote-unescape',
        function($line as xs:string, $options as map:map) as xs:string {
            replace($line, map:get($options, 'quote-escape'), map:get($options, 'quote'))
        })
    => map:with('post-parse',
        function($line as xs:string*, $options as map:map) as item()* {
            element { map:get($options, '!record-element') } 
                {
                    $line ! element { map:get($options, '!field-element' ) }
                        { . }
                }
        })
    => map:with('report-error',
        function($line as xs:string?, $line-no as xs:integer?, $message as xs:string, $options as map:map?) {
            fn:error((), 'CSV:ERROR', ($message, $line, $line-no))
         } );

declare option xdmp:mapping "false";

(:~ 
 : Given a sequence of lines, apply CSV conversion to each one, returning a sequence of results
 : (by default, record elements containing field elements)
 : @param $lines the sequence of lines
 : @param $options the options map
 : @return a sequence of results (generated through map:get($options, 'post-parse'))
 :)
declare function csv:parse-sequence($lines as xs:string*, $options as map:map) as item()* {
    let $working-options := csv:working-options($options)
    let $post-parse as function(xs:string*, map:map) as item()* := map:get($working-options, 'post-parse')
    return for $line at $pos in $lines
      let $parsed as xs:string* := csv:parse-line($line, $pos,  $working-options)
      return $post-parse($parsed, $working-options)
};

(:~
: Build a set of working options by mergeing the user and default options. These are then used to
: generate the calculated options used by the parsing process. The user can override calculated
: options by providing values in $user-options (although this is probabaly never useful).
: The following options are caclulated -
:      !ql - the number of characters to add when parsing a quoted
:          field to find the start of the next field
:      !dl - the number of characters to add when parsing an unqoted
:          field to find the start of the next field
:      !line-filter - partial application of the line filter function
:            to avoid passing in options on every call
:      !field-filter - as above but for the field filter
:      !internal-quote-escape - as above but for the quote escape function
:      !internal-quote-unescape - as above but for the quote unescape function
:      !field-element - QName for field elements
:      !record-element - QName for record elements
: @param $user-options A map of user options
: @return A map of working options.
:)
declare function csv:working-options($user-options as map:map) as map:map {
    let $working-options := map:new(($DEFAULT-OPTIONS, $user-options))
    let $calculated-options := map:map() 
        => map:with('!field-element', csv:element-qname('field', $working-options))
        => map:with('!record-element', csv:element-qname('record', $working-options))
        => map:with('!dl',  string-length(map:get($working-options, 'field-delimiter')) + 1)
        => map:with('!ql', string-length(map:get($working-options, 'quote')) * 2 + 
            string-length(map:get($working-options, 'field-delimiter')) + 1)
        => map:with('!line-filter', map:get($working-options, 'line-filter')(?, $working-options))
        => map:with('!field-filter', map:get($working-options, 'field-filter')(?, $working-options))
        => map:with('!internal-quote-unescape', map:get($working-options, 'internal-quote-unescape')(?, $working-options))
        => map:with('!internal-quote-escape', map:get($working-options, 'internal-quote-escape')(?, $working-options))

    (: merge these such that user settings will override calculated just in case :)
    return map:new(($working-options, $calculated-options))
};

(:~
 : Return a map entry for the field or recored element or call the error handler if it's 
 : not possible
 : @param $name - either 'field' or 'record'
 : @param $options - options map to be passed to error handler if required
 : @return QName for field name
:)
declare private function csv:element-qname($name as xs:string, $options as map:map) as xs:QName {
    try {
        xs:QName(map:get($options, $name || '-element'))
    } catch ($e) {
        map:get($options, 'report-error')((), (),
            map:get($options, $name || '-element') || ' is not a valid QName.', $options)
    }
};

declare private function csv:parse-line($line as xs:string, $line-no as xs:integer, $options as map:map) as xs:string* {
    let $filtered as xs:string? := map:get($options, '!line-filter')($line)
    return if (fn:not(fn:contains($line, map:get($options, 'field-delimiter')))) 
      then map:get($options, 'report-error')($line, $line-no, 'No field delimiter found in this line', $options)
        else if (exists($filtered))
          then csv:parse-line-recurse(
              map:get($options, '!internal-quote-escape')($filtered), 
              $options) 
              ! map:get($options, '!internal-quote-unescape')(.) 
              ! map:get($options, '!field-filter')(.)
          else ()
};

declare private function csv:parse-line-recurse($line as xs:string, $options as map:map) as xs:string* {
    
    let $d := map:get($options, 'field-delimiter')
    let $q := map:get($options, 'quote')
    
    return       
        (: just a string - quotes  but one or more fields :)
        if (not(contains($line, $d))) then tokenize($line, $q) 
        
        (: if it starts with a quote ... :)
        else if (starts-with($line, $q))                    
        then 
            let $first-field := substring-before(substring-after($line, $q), $q)
            let $remainder := substring($line, string-length($first-field) + map:get($options, '!ql'))
            return ($first-field, csv:parse-line-recurse($remainder, $options))
        
        (: there is a quote somewhere but it's not first :)                    
        else 
            let $first-field := substring-before($line, $d)
            let $remainder := substring($line, string-length($first-field) + map:get($options, '!dl'))
            return ($first-field, csv:parse-line-recurse($remainder, $options))
 };