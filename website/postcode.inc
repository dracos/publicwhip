<?php

/////////////////////////////////////////////////////////////////////////////
// This is now a copy from the theyworkforyou.com code, these functions
// are in utility.php there, so we add them at the start.

function validate_postcode($postcode)
{
    // See http://www.govtalk.gov.uk/gdsc/html/noframes/PostCode-2-1-Release.htm
    $postcode = trim($postcode);

    $in = 'ABDEFGHJLNPQRSTUWXYZ';
    $fst = 'ABCDEFGHIJKLMNOPRSTUWYZ';
    $sec = 'ABCDEFGHJKLMNOPQRSTUVWXY';
    $thd = 'ABCDEFGHJKSTUW';
    $fth = 'ABEHMNPRVWXY';
    $num = '0123456789';
    $nom = '0123456789';
    $gap = '\s\.';

    if (preg_match("/^[$fst][$num][$gap]*[$nom][$in][$in]$/i", $postcode) ||
        preg_match("/^[$fst][$num][$num][$gap]*[$nom][$in][$in]$/i", $postcode) ||
        preg_match("/^[$fst][$sec][$num][$gap]*[$nom][$in][$in]$/i", $postcode) ||
        preg_match("/^[$fst][$sec][$num][$num][$gap]*[$nom][$in][$in]$/i", $postcode) ||
        preg_match("/^[$fst][$num][$thd][$gap]*[$nom][$in][$in]$/i", $postcode) ||
        preg_match("/^[$fst][$sec][$num][$fth][$gap]*[$nom][$in][$in]$/i", $postcode)
    ) {
        return true;
    } else {
        return false;
    }
}

//////////////////////////////////////////////////////////////////////////////

// Whether the form of the postcode is one or not
function is_postcode($postcode)
{
    $postcode = trim($postcode);
    //return preg_match("/^[A-Z]{1,2}\d[A-Z\d]? ?\d[ABD-HJLNP-UW-Z]{2}$/i", $postcode);
    return validate_postcode($postcode);    // in utility.php
}

function postcode_to_candidates($db, $postcode)
{
    $postcode = trim($postcode);
    if (!is_postcode($postcode)) {
        return array('ERROR' => "The postcode was malformed.");
    }
    $useful_keys = array(
        "WMC" => true,
        "SPC" => true,
        "SPE" => true
    );

    $response = get_text_from_http("https://www.yournextmp.com",
        80,
        "search?query=" . urlencode($postcode));
    return $response;
}


# This function returns a map of constituency type to
# name of constituency.  For example, a Cambridge postcode
# might return:
#   array( "WMC" => "South Cambridgeshire" )
# ... whereas a postcode in Edinburgh might return:
#   array( "WMC" => "Edinburgh East",
#          "SPC" => "Edinburgh Central",
#          "SPE" => "Lothians" )
# If there's any error, then we return something like:
#   array( "ERROR" => "That isn't a postcode" )
function postcode_to_constituencies($db, $postcode)
{
    global $mapItApiKey;
    $postcode = trim($postcode);
    if (!is_postcode($postcode)) {
        pw_handle_404('Postcode malformed','Sorry, the post code you entered did not look correct.');
        exit();
    }
    $useful_types = array("WMC", "SPC", "SPE");

    $postcode = preg_replace('/[^A-Z0-9]/', '', strtoupper($postcode));
    $cacheFile = __DIR__ . '/../postcodecache/' . $postcode . '.json';
    $response = false;
    $readFromCache = false;
    if (file_exists($cacheFile)) {
        $response = file_get_contents($cacheFile);
        $readFromCache = true;
    } else {
        try {
            $response = get_text_from_http('mapit.mysociety.org', 80,
                '/postcode/' . rawurlencode($postcode) . '?api_key='.$mapItApiKey);
        } catch (Exception $e) {
            $response = '';
        }
    }
    if (!$response) {
        pw_handle_404('System error','Sorry, there was a temporary issue looking up that postcode. Please try again later.');
        exit();
    }
    if ('' === trim($response)) {
        pw_handle_404('System error','Sorry, there was a temporary issue looking up that postcode. Please try again later.');
        exit();
    }
    $jsonResponse = json_decode($response, true);
    if ($jsonResponse['error']) {
        if ($jsonResponse['code']===404) {
            file_put_contents($cacheFile, $response);
            pw_handle_404('Postcode not recognised','Sorry, the post code you entered was not recognised');
            exit();
        }
        error_log('Postcode server: ' . $response);
        return array("ERROR" => "The postcode server returned an error.");
    }

    $final_result = array();
    foreach ($jsonResponse['areas'] as $match) {
        $type = $match['type'];
        $name = $match['name'];
        if (!in_array($type, $useful_types)) {
            continue;
        }
        $house = ($type == 'WMC' ? 'commons' : 'scotland');
        $constituency = normalise_constituency_name(strtolower($name), $house);
        if (!$constituency) {
            $constituency = "[Unknown $house constituency: '$name']";
        }
        $final_result[$type] = $constituency;
    }
    if (!$final_result) {
        return array("ERROR" => "There was an unexpected response when looking up the postcode.");
    }
    if (false === $readFromCache) {
        file_put_contents($cacheFile, $response);
    }
    return $final_result;
}

function get_text_from_http($domain, $port, $path)
{
    $useCurl = false;
    if (true === function_exists('curl_init')) {
        $useCurl = true;
    }
    if (true === $useCurl) {
        $curl = curl_init('https://' . $domain . $path);
        curl_setopt($curl, CURLOPT_RETURNTRANSFER, true);
        $output = curl_exec($curl);
        curl_close($curl);
        return $output;
    }
    $contents = file_get_contents('https://' . $domain . $path);
    return $contents;

    /**
     * Old code
     */
    $file = ""; // just to be safe. Dunno, if this is really needed
    $timeout = 5;
    $fp = @fsockopen($domain, $port, $errno, $errstr, $timeout);
    if ($fp) {
        stream_set_timeout($fp, $timeout);
        $sockstart = getmicrotime(); # feof doesn't time out, so we have to measure ourselves also
        $out = "GET $path HTTP/1.0\r\n";
        $out .= "Host: " . $domain . "\r\n";
        $out .= "Connection: Close\r\n\r\n";

        fwrite($fp, $out);
        $inbody = false;
        while (!feof($fp) and (getmicrotime() < $sockstart + $timeout)) {
            $line = fgets($fp, 1024);
            if ($line == "\r\n") {
                $inbody = true;
            }
            if ($inbody) {
                $file .= $line;
            }
        }
        if (getmicrotime() >= $sockstart + $timeout) {
            trigger_error("Postcode database is not working.  Connection timed out.", E_USER_WARNING);
            return '';
        }
        fclose($fp);
    } else {
        trigger_error("Postcode database is not working.  $errstr.", E_USER_WARNING);
        return '';
    }
    return $file;
}

function postcode_to_constituency($db, $postcode, $pc_parl = "2010")
{
    $postcode = trim($postcode);

    global $last_postcode;
    global $last_postcode_value;

    if ($last_postcode == $postcode) {
        #debug ("TIME", "Postcode $postcode looked up last time, is $last_postcode_value .");
        return $last_postcode_value;
    }

    #$start = getmicrotime();

    if ($pc_parl && $pc_parl != 2010) {
        trigger_error("Unknown postcode parliament $pc_parl", E_USER_ERROR);
    }
    $areas = postcode_to_constituencies($db, $postcode);
    if ($areas['ERROR']) {
        return '';
    }

    $ret = $areas['WMC'];

    #$duration = getmicrotime() - $start;
    #debug ("TIME", "Postcode $postcode lookup took $duration seconds, returned $ret.");

    $last_postcode = $postcode;
    $last_postcode_value = $ret;
    return $ret;
}

