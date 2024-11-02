/// This file contains the implementation of the Sensorx widget, which is a
/// stateful widget that monitors accelerometer and gyroscope data, speaks
/// activity names using text-to-speech, and saves the data to a CSV file.
///
/// The widget uses various packages including:
/// - csv: For converting data to CSV format.
/// - flutter/material.dart: For building the UI.
/// - flutter/services.dart: For text input formatting.
/// - flutter_tts: For text-to-speech functionality.
/// - path_provider: For accessing the device's file system.
/// - sensors_plus: For accessing sensor data.
/// - wakelock_plus: For keeping the device awake during monitoring.

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// The Sensorx widget is a stateful widget that monitors sensor data and
/// saves it to a CSV file.
class Sensorx extends StatefulWidget {
  const Sensorx({super.key});

  @override
  State<Sensorx> createState() => _SensorxState();
}

class _SensorxState extends State<Sensorx> {
  /// The current date.
  final DateTime _currentDate = DateTime.now();

  /// Timer to update the current time every second.
  late Timer _timer;

  /// The current time.
  DateTime _currentTime = DateTime.now();

  /// List of activity items.
  final List<String> _items = [];

  /// Controller for the text input field for adding items.
  final TextEditingController _textController = TextEditingController();

  /// Controller for the text input field for setting the duration.
  final TextEditingController _textControllerDuration = TextEditingController();

  /// Instance of FlutterTts for text-to-speech functionality.
  final FlutterTts _tts = FlutterTts();

  /// Accelerometer data.
  double _accelerometerX = 0.0;
  double _accelerometerY = 0.0;
  double _accelerometerZ = 0.0;

  /// Gyroscope data.
  double _gyroscopeX = 0.0;
  double _gyroscopeY = 0.0;
  double _gyroscopeZ = 0.0;

  /// Flag to indicate if monitoring is in progress.
  bool _isMonitoring = false;

  /// Total number of records collected.
  int _totalRecords = 0;

  /// Maximum number of records to be collected.
  late int _maxRecords;

  /// Starts monitoring the sensors and collects data for each activity item.
  ///
  /// [items] is the list of activity items to be monitored.
  Future<void> _startSensors(List<String> items) async {
    setState(() {
      _isMonitoring = true;
    });
    await _speak();
    List<List<dynamic>> allSensorData = []; // List to accumulate all records

    // Add header to the data list
    allSensorData.add(
        ["ActivityName", "ActivityDate", "Ax", "Ay", "Az", "Gx", "Gy", "Gz"]);

    // Listen to accelerometer events
    accelerometerEvents.listen((AccelerometerEvent event) {
      setState(() {
        _accelerometerX = event.x;
        _accelerometerY = event.y;
        _accelerometerZ = event.z;
      });
    });

    // Listen to gyroscope events
    gyroscopeEvents.listen((GyroscopeEvent event) {
      setState(() {
        _gyroscopeX = event.x;
        _gyroscopeY = event.y;
        _gyroscopeZ = event.z;
      });
    });

    for (String item in items) {
      await _tts.speak("La actividad $item comenzará en");
      await _waitForTTS();

      // Countdown of 5 seconds before starting to record
      for (int countdown = 5; countdown > 0; countdown--) {
        _tts.speak(countdown.toString());
        await Future.delayed(const Duration(seconds: 1));
      }

      // Record data for the specified duration
      int totalRecords = 0;
      int durationInSeconds = _textControllerDuration.text.isNotEmpty
          ? int.parse(_textControllerDuration.text)
          : 180;
      const int recordsPerSecond = 100;
      _maxRecords = _items.length * (durationInSeconds - 1) * 100;

      Timer.periodic(const Duration(milliseconds: 10), (Timer t) {
        if (totalRecords >= durationInSeconds * recordsPerSecond) {
          t.cancel();
        } else {
          final String formattedTime =
              "${_currentTime.hour.toString().padLeft(2, '0')}:${_currentTime.minute.toString().padLeft(2, '0')}:${_currentTime.second.toString().padLeft(2, '0')}.${_currentTime.millisecond.toString().padLeft(3, '0')}";

          allSensorData.add([
            // Accumulate the records
            item,
            formattedTime,
            _accelerometerX,
            _accelerometerY,
            _accelerometerZ,
            _gyroscopeX,
            _gyroscopeY,
            _gyroscopeZ,
          ]);

          totalRecords++;
        }
        setState(() {
          _totalRecords++;
        });
      });

      await Future.delayed(Duration(
          seconds: durationInSeconds)); // Wait for the specified duration
    }

    // Save all data after recording all items
    await _saveToCSV(allSensorData);
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      setState(() {
        _currentTime = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  /// Configures the text-to-speech settings.
  Future<void> _speak() async {
    await _tts.setLanguage("es-ES");
    await _tts.setPitch(1.0);
  }

  /// Waits for the text-to-speech to complete.
  Future<void> _waitForTTS() async {
    Completer<void> completer = Completer<void>();
    _tts.setCompletionHandler(() {
      completer.complete();
    });
    return completer.future;
  }

  /// Removes an item from the list at the specified index.
  ///
  /// [index] is the index of the item to be removed.
  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
  }

  /// Adds a new item to the list.
  void _addItem() {
    if (_textController.text.isNotEmpty) {
      setState(() {
        _items.add(_textController.text);
        _textController.clear();
      });
    }
  }

  /// Saves the collected data to a CSV file.
  ///
  /// [csvData] is the list of data to be saved.
  Future<void> _saveToCSV(List<List<dynamic>> csvData) async {
    final List<List<dynamic>> rows = csvData;

    String csv = const ListToCsvConverter().convert(rows);
    final directory = await getDownloadsDirectory();
    final path = "${directory!.path}/SensorX_Data.csv";
    final file = File(path);
    await file.writeAsString(csv);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Archivo guardado en $path')),
    );

    setState(() {
      _isMonitoring = false;
      _totalRecords = 0;
      _maxRecords = 1;
      WakelockPlus.disable();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.yellow,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    '${_currentDate.day.toString().padLeft(2, '0')}-${_currentDate.month.toString().padLeft(2, '0')}-${_currentDate.year.toString().padLeft(4, '0')}',
                    style: const TextStyle(fontSize: 25),
                  ),
                  const Expanded(
                    child: SizedBox(),
                  ),
                  Text(
                    '${_currentTime.hour.toString().padLeft(2, '0')}:${_currentTime.minute.toString().padLeft(2, '0')}:${_currentTime.second.toString().padLeft(2, '0')}',
                    style: const TextStyle(fontSize: 25),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Center(
                child: ElevatedButton(
                  onPressed: () async {
                    setState(() {
                      _isMonitoring = false;
                      _maxRecords = 1;
                      WakelockPlus.enable();
                    });
                    await _startSensors(_items);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                      _isMonitoring ? 'Monitoreando...' : 'Iniciar Monitoreo'),
                ),
              ),
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: _isMonitoring ? _totalRecords / _maxRecords : 0,
                minHeight: 20,
                backgroundColor: Colors.grey[300],
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.black),
                borderRadius: BorderRadius.circular(999),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 500,
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 3,
                      crossAxisSpacing: 25,
                      mainAxisSpacing: 25),
                  itemCount: _items.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return ElevatedButton(
                        onPressed: () {
                          _showAddDialog();
                        },
                        style: ElevatedButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.black),
                        child: const Icon(
                          Icons.add,
                          size: 50,
                          color: Colors.white,
                        ),
                      );
                    } else {
                      return GestureDetector(
                        onLongPress: () {
                          _removeItem(index - 1);
                        },
                        child: ElevatedButton(
                          onPressed: () {},
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                          ),
                          child: Text(
                            _items[index - 1],
                            style: const TextStyle(
                                fontSize: 20, color: Colors.white),
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
              Container(
                width: 100,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: TextField(
                  controller: _textControllerDuration,
                  keyboardType: TextInputType.number, // Solo aceptar números
                  textAlign: TextAlign.center,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly
                  ], // Filtrar solo números
                  decoration: const InputDecoration(
                    hintText: 'Duración',
                    border: InputBorder.none,
                    filled: true,
                    fillColor: Colors.transparent,
                    contentPadding: EdgeInsets.fromLTRB(10, 10, 10, 10),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Center(
                child: Text(
                  "Rafael Said Hernández Demeneghi",
                  style: TextStyle(
                    fontSize: 20,
                    color: Colors.black,
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Agregar nuevo elemento'),
          content: TextField(
            controller: _textController,
            decoration:
                const InputDecoration(hintText: 'Escribe el texto aquí'),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _addItem();
                Navigator.of(context).pop();
              },
              child: const Text('Agregar'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );
  }
}
