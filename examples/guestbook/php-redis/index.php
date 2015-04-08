<?

set_include_path('.:/usr/share/php:/usr/share/pear:/vendor/predis');

error_reporting(E_ALL);
ini_set('display_errors', 1);

require 'predis/autoload.php';

if (isset($_GET['cmd']) === true) {
  header('Content-Type: application/json');
  if ($_GET['cmd'] == 'set') {
    $client = new Predis\Client([
      'scheme' => 'tcp',
      'host'   => getenv('REDIS_MASTER_PORT_6379_TCP_ADDR'),//'redis-master',
      'port'   => 6379,
    ]);
    
    $client->set($_GET['key'], $_GET['value']);
    $client->save();
    print('{"message": "Updated"}');
  } else {
    $client = new Predis\Client([
      'scheme' => 'tcp',
      'host'   => getenv('REDIS_SLAVE_PORT_6379_TCP_ADDR'),//'redis-slave',
      'port'   => 6379,
    ]);

    $value = $client->get($_GET['key']);
    print('{"data": "' . $value . '"}');
  }
} else {
  phpinfo();
} ?>
