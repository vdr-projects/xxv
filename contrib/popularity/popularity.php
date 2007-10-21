<?php
/**
* @version $Id $
* @package Xtreme eXtension for VDR
* @copyright Copyright (C) 2007 xxv team. All rights reserved.
* @license http://www.gnu.org/copyleft/gpl.html GNU/GPL, see LICENSE.php
* xxv is free software. This version may have been modified pursuant
* to the GNU General Public License, and as distributed it includes or
* is derivative of works licensed under the GNU General Public License or
* other free or open source software licenses.
* See COPYRIGHT.php for copyright notices and details.
*/

// Set flag that this is a parent file
define( '_VALID_MOS', 1 );

// Pull in the NuSOAP code
require_once('popularity/nusoap.php');

// Create the server instance
$server = new soap_server();
// Initialize WSDL support
$server->configureWSDL('popularity', 'urn:popularity');


function opendatabase() {

  require( 'globals.php' );
  require_once( 'configuration.php' );
  require_once( $mosConfig_absolute_path . '/includes/database.php' );

  $database = new database( $mosConfig_host, $mosConfig_user, $mosConfig_password, $mosConfig_db, $mosConfig_dbprefix );
  if ($database->getErrorNum()) {
  	$mosSystemError = $database->getErrorNum();
  	$basePath = dirname( __FILE__ );
  	include $basePath . '/configuration.php';
  	include $basePath . '/offline.php';
  	exit();
  }
  $database->debug( $mosConfig_debug );

  return $database;
}

////////////////////////////////////////////////////////////////////////////////
// Register the method to expose
$server->register('getUsrKey',                // method name
    array('key'    => 'xsd:string'),          // input parameters
    array('return' => 'xsd:string'),          // output parameters
    'urn:popularity',                         // namespace
    'urn:popularity#getUsrKey',               // soapaction
    'rpc',                                    // style
    'encoded',                                // use
    'A connection test for clients.'          // documentation
);
// A connection test for clients.
function getUsrKey($key) {
    $usrkey = $key;
    return $usrkey;
}


////////////////////////////////////////////////////////////////////////////////
// Register the method to expose
$server->register('getServerTime',           // method name
    array('key' => 'xsd:string'              // input parameters 
          ),                                 
    array('return' => 'xsd:int'),            // output parameters
    'urn:popularity',                        // namespace
    'urn:popularity#getServerTime',          // soapaction
    'rpc',                                   // style
    'encoded',                               // use
    'Return the time from server.'           // documentation
);
// Return the time from server
function getServerTime($key) {

    $database = opendatabase();

    $query = "SELECT UNIX_TIMESTAMP(NOW())";
		$database->setQuery( $query );
		$servertime = $database->loadResult();

    return $servertime;
}

////////////////////////////////////////////////////////////////////////////////
// Register the method to expose
$server->register('getEventLevel',           // method name
    array('key' => 'xsd:string',             // input parameters 
          'id' => 'xsd:int'),                
    array('return' => 'xsd:float'),          // output parameters
    'urn:popularity',                        // namespace
    'urn:popularity#getEventLevel',          // soapaction
    'rpc',                                   // style
    'encoded',                               // use
    'Return the average level from Event.'   // documentation
);
// Return the average level from Event
function getEventLevel($key,$id) {

    $database = opendatabase();

    $query = "SELECT AVG(level)"
			. " FROM #__popularity"
			. " WHERE id = " . (int) $id
			;
		$database->setQuery( $query );
		$average = $database->loadResult();

    return $average;
}

////////////////////////////////////////////////////////////////////////////////
// Register the method to expose
$server->register('setEventLevel',           // method name
    array('key' => 'xsd:string',             // input parameters 
          'eventid' => 'xsd:int', 
          'level' => 'xsd:int', 
          'stoptime' => 'xsd:int'), 
    array('return' => 'xsd:int'),            // output parameters
    'urn:popularity',                        // namespace
    'urn:popularity#setEventLevel',          // soapaction
    'rpc',                                   // style
    'encoded',                               // use
    'Set a level to event.'                  // documentation
);
// Set a level to event.
function setEventLevel($key,$id,$level,$stoptime) {

    if((int)$level <= 0) {
      $level = 0;
    } else {
      if((int)$level >= 10) {
        $level = 10;
      }
    }

    $database = opendatabase();

		$query = "REPLACE INTO #__popularity"
		. " (user, id, level, stoptime)"
		. " VALUES ( " . $database->Quote( $key ) . ", "
		                     . (int)$id . ", "
		                     . (int)$level . ", "
		. " FROM_UNIXTIME( " . (int)$stoptime . " )"
    . " )"
		;
		$database->setQuery( $query );
    if (!$database->query()) {
  	  die($database->stderr(true));
      return 1;
		}
    return 1;
}

////////////////////////////////////////////////////////////////////////////////
// Register the method to expose
$server->register('deleteEvent',           // method name
    array('key' => 'xsd:string',           // input parameters 
          'eventid' => 'xsd:int'),         
    array('return' => 'xsd:int'),          // output parameters
    'urn:popularity',                      // namespace
    'urn:popularity#deleteEvent',          // soapaction
    'rpc',                                 // style
    'encoded',                             // use
    'Delete an event from database.'       // documentation
);
// Delete an event from database.
function deleteEvent($key,$id) {

    $database = opendatabase();

    $query = "DELETE"
			. " FROM #__popularity"
			. " WHERE id = " . (int) $id
			;
		$database->setQuery( $query );
    if (!$database->query()) {
  	  die($database->stderr(true));
      return 0;
		}

    return 1;
}

// Delete expired events from selected database.
function expired($database) {

    $query = "DELETE"
			. " FROM #__popularity"
			. " WHERE stoptime < NOW()"
			;
		$database->setQuery( $query );
    if (!$database->query()) {
  	  die($database->stderr(true));
      return 0;
		}

    return 1;
}

////////////////////////////////////////////////////////////////////////////////
// Register the method to expose
$server->register('clear',                 // method name
    array('key' => 'xsd:string'            // input parameters 
          ),                    
    array('return' => 'xsd:int'),          // output parameters
    'urn:popularity',                      // namespace
    'urn:popularity#clear',                // soapaction
    'rpc',                                 // style
    'encoded',                             // use
    'Delete old events from database.'     // documentation
);
// Delete old events from database.
function clear($key) {

    $database = opendatabase();
    return expired($database);
}


////////////////////////////////////////////////////////////////////////////////

$server->wsdl->addComplexType(
    'EventLevel',
    'complexType',
    'struct',
    'all',
    '',
    array(
        'eventid' => array('name'=>'eventid','type'=>'xsd:int'),
        'level' => array('name'=>'level','type'=>'xsd:float')
    )
);

$server->wsdl->addComplexType(
    'EventLevelArray',
    'complexType',
    'array',
    '',
    'SOAP-ENC:Array',
    array(),
    array(
        array('ref'=>'SOAP-ENC:arrayType','wsdl:arrayType'=>'tns:EventLevel[]')
    ),
    'tns:EventLevel'
);

// Register the method to expose
$server->register('getEventLevels',        // method name
    array('key' => 'xsd:string'            // input parameters 
          ),                   
    array('return' => 'tns:EventLevelArray'),// output parameters
    'urn:popularity',                      // namespace
    'urn:popularity#getEventLevels',       // soapaction
    'rpc',                                 // style
    'encoded',                             // use
    'Return the average levels from events.'// documentation
);
// Return the average Levels from Events.
function getEventLevels($key) {

    $database = opendatabase();

    if(!expired($database)) {
      return 0;
    }

    $query = "SELECT id, AVG(level) as level"
			. " FROM #__popularity"
			. " GROUP BY id"
			;
		$database->setQuery( $query );
		$rows = $database->loadObjectList();
  	if(empty($rows)) {
				return 0;
		}

    $result = array();
		foreach ($rows as $row) {
        $result[] = array(
                   'eventid' => $row->id,
                   'level' => $row->level
                   );
		}
    return $result;
}


////////////////////////////////////////////////////////////////////////////////

$server->wsdl->addComplexType(
    'TopTen',
    'complexType',
    'struct',
    'all',
    '',
    array(
        'eventid' => array('name'=>'eventid','type'=>'xsd:int'),
        'level' => array('name'=>'level','type'=>'xsd:float'),
        'count' => array('name'=>'count','type'=>'xsd:int'),
        'rank' => array('name'=>'rank','type'=>'xsd:float')
    )
);

$server->wsdl->addComplexType(
    'TopTenArray',
    'complexType',
    'array',
    '',
    'SOAP-ENC:Array',
    array(),
    array(
        array('ref'=>'SOAP-ENC:arrayType','wsdl:arrayType'=>'tns:TopTen[]')
    ),
    'tns:TopTen'
);

// Register the method to expose
$server->register('getTopTen',             // method name
    array('key' => 'xsd:string',           // input parameters 
          'limit' => 'xsd:int'),
    array('return' => 'tns:TopTenArray'),  // output parameters
    'urn:popularity',                      // namespace
    'urn:popularity#getTopTen',            // soapaction
    'rpc',                                 // style
    'encoded',                             // use
    'Return the topten list.'              // documentation
);
// Return the topten list.
function getTopTen($key,$limit) {

    $database = opendatabase();

    if(!expired($database)) {
      return 0;
    }

    if((int)$limit <= 0) {
      $limit = 10;
    }

    $query = "SELECT id, AVG(level) as level, COUNT(*) as c, AVG(level)*COUNT(*) as rank"
			. " FROM #__popularity"
			. " GROUP BY id ORDER by rank DESC LIMIT " . (int) $limit
			;
		$database->setQuery( $query );
		$rows = $database->loadObjectList();
  	if(empty($rows)) {
				return 0;
		}

    $result = array();
		foreach ($rows as $row) {
        $result[] = array(
                   'eventid' => $row->id,
                   'level' => $row->level,
                   'count' => $row->c,
                   'rank' => $row->rank
                   );
		}
    return $result;
}


////////////////////////////////////////////////////////////////////////////////
// Register the method to expose
$server->register('createtable',           // method name
    array('key' => 'xsd:string'            // input parameters 
          ),                               
    array('return' => 'xsd:int'),          // output parameters
    'urn:popularity',                      // namespace
    'urn:popularity#createtable',          // soapaction
    'rpc',                                 // style
    'encoded',                             // use
    'create table into database.'          // documentation
);
// Delete an event from database.
function createtable($key) {

    $database = opendatabase();

    $query = "CREATE TABLE IF NOT EXISTS #__popularity ("
			. " user varchar(16) NOT NULL default '',"
			. " id int unsigned NOT NULL default '0',"
			. " level int default NULL,"
			. " stoptime datetime NOT NULL,"
			. " UNIQUE KEY `event` (`user`,`id`)"
			. " )"
    ;
		$database->setQuery( $query );
    if (!$database->query()) {
  	  die($database->stderr(true));
      return 0;
		}

    return 1;
}

////////////////////////////////////////////////////////////////////////////////
// Use the request to (try to) invoke the service
$HTTP_RAW_POST_DATA = isset($HTTP_RAW_POST_DATA) ? $HTTP_RAW_POST_DATA : '';
$server->service($HTTP_RAW_POST_DATA);
?>

