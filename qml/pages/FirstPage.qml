// Main View

import QtQuick 2.0
import Sailfish.Silica 1.0
import QtPositioning 5.4
import Nemo.Configuration 1.0
import org.nemomobile.systemsettings 1.0

Page {
    id: mainPage
     allowedOrientations: Orientation.Portrait
    // secret to send upon requests. Not sure if needed.
    readonly property string post_secret : "<apikeyhere>";
    // variable to store device Id. Will be persisted on device over sessions once generated.
    property string deviceId: "";
    // baseUrl of routechoices server api
    readonly property string baseUrl : "https://api.routechoices.com";
    // Variable to store the last recorded coordinates
    property var lastCoordinates: ({});
    // buffer where to store coordinates that will be sent to server later
    property var coordinateBuffer: [];
    // variable to store last battery level
    property int lastBatteryLevel : 0;
    // counter to prevent battery level checking seldomly in same timer handler
    property int counter: 0;
    // wait safety counter to limit polling until device info is available
    property int initCounter: 100;
    // how many coordinates need to be in buffer to send
    readonly property int minimumCoordinatesToSend: 2;
    // how many meters location needs to change until we accept it
    readonly property double minLocationDistanceDiff: -1;
    // deviceInfo for IMEI
    property DeviceInfo deviceInfo: DeviceInfo {}
    // battery level we get from here
    property BatteryStatus batteryInfo: BatteryStatus {}
    // define how many seconds off server and device can be?
    readonly property int maxTimeDiff: 60*60;
    readonly property int positioningUpdateInterval: 5 * 1000;
    readonly property int postCoordinatesInterval: 10 * 1000;
    readonly property int pollImeiCodeInterval: 1 * 1000;

    // Add an Image as the background
    Image {
        source: "banner2.png"
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
    }
    // Title header, for now
    TextField {
        id: header
        placeholderText: qsTr("Routechoices Tracker")
        width: parent.width * 0.8
        horizontalAlignment: TextInput.AlignHCenter // Align text to the center
        anchors {
            topMargin:200
            horizontalCenter: appImage.horizontalCenter
        }
    }
    // Satellite icon to show user when positioning is providing valid coordinates.
    Icon {
        id: gpsImage
        source: "image://theme/icon-m-gps"
        visible: false
        anchors.top: header.bottom
        horizontalAlignment: TextInput.AlignHCenter // Align  to the center
    }
    // Internet icon to show when connection to server exists.
    Icon {
        id: connectionIcon
        source: "image://theme/icon-m-website"
        visible: false
        anchors.top: gpsImage.bottom
        horizontalAlignment: TextInput.AlignHCenter // Align  to the center
    }
    // RC logo pic
    Image {
        id: appImage
        source: "RouteChoices.png"
        anchors.centerIn: parent
        anchors.top: gpsImage.bottom
    }

    // Button to get start the GPS tracking and send to server
    Button {
        id: startButton
        text: qsTr("Start Tracking")
        onClicked: {
            startTracking();
        }
        enabled: false
        anchors {
            top: appImage.bottom
            horizontalCenter: coordinatesText.horizontalCenter
        }
        border.color: "#EEEEEE"
        color: "#3498db"
    }

    // Text box to display GPS coordinates. Should hide in non debug versions?
    TextField {
        id: coordinatesText
        placeholderText: qsTr("GPS Coordinates will appear here")
        anchors {
            bottom: deviceIdText.top
            horizontalCenter: appImage.horizontalCenter
        }
        visible: false
    }
    // Text box to display DevID
    TextField {
        id: deviceIdText
        placeholderText: qsTr("Initializing, please wait")
        anchors {
            bottom: parent.bottom
            horizontalCenter: appImage.horizontalCenter
        }
        width: parent.width * 0.8 // Set the width based on your design
        horizontalAlignment: TextInput.AlignHCenter // Align text to the center
    }

    // column would end here }
    Component.onCompleted: {
        lastCoordinates = null;
        //if (Qt.debug.isDebugBuild)
        {
            coordinatesText.visible = true;

        }

        checkServerTime();
    }

    function checkServerTime()
    {
        // Create XmlHttpRequest
       var xhr = new XMLHttpRequest();

       // Setup the request
       xhr.open("GET", baseUrl + "/time/", true);
       xhr.setRequestHeader("Content-Type", "application/json");

       // Handle the response
       xhr.onreadystatechange = function() {
           if (xhr.readyState === XMLHttpRequest.DONE) {
               if (xhr.status === 200) {
                   connectionIcon.visible = true;
                   // Parse the JSON response
                   var jsonResponse = JSON.parse(xhr.responseText);

                   // Access the 'time' property from the JSON response
                   var timeValue = jsonResponse.time;

                   console.log("SERVERTime:", timeValue);

                   var timestamp = new Date().getTime() / 1000;
                   console.log("DeviceTime:", timestamp.toString());
                   var timeDiff = Math.abs(timestamp- timeValue);
                   if (timeDiff <= maxTimeDiff){
                       // within time diff lets start polling for the Imei
                       initTimer.start();
                   }
                   else {
                       coordinatesText.text = "Check device clock!";
                   }

               } else {
                   coordinatesText.text = "Failed to retrieve server time " + xhr.status.toString();
                   console.error("HTTP request failed with status:", xhr.status, xhr.statusText);
                   connectionIcon.visible = false;
               }
           }
       };

       // Send the request
       xhr.send();
   }

    function initializePage() {
        // we need to wait until phone services warmed up to get IMEI. initCounter will eventually fall back to using generated ID
        // in case IMEI not available due to Phone permission not granted or other reasons.

        if (deviceInfo.imeiNumbers.length > 0 || initCounter-- <= 0) {
        console.log("IMEI: " + deviceInfo.imeiNumbers[0]);
         // Get or generate the device ID
        requestDeviceId();

        updateBatteryLevel();
        startButton.enabled = true;
        }
        else {
            console.log("Init not yet complete...");
            initTimer.start(); // lets try again later
        }
    }

    PositionSource {
        id: src
        updateInterval: positioningUpdateInterval
        active: true
        onSourceErrorChanged: {
        if (src.sourceError !== PositionSource.NoError)
            coordinatesText.text = "LocationError: " + src.sourceError;
        }
        onPositionChanged: {
            var positionSource = src;
            if (positionSource.sourceError === PositionSource.NoError && positionSource.position.latitudeValid && positionSource.position.longitudeValid ) {
                var latitude = positionSource.position.coordinate.latitude;
                var longitude = positionSource.position.coordinate.longitude;
                gpsImage.visible = true;
                // Get the current time in seconds since the Unix epoch
                var timestamp = new Date().getTime() / 1000;

                coordinatesText.text = "La: " + latitude.toFixed(3).toString() + "| Lo: " + longitude.toFixed(3).toString() +
                        "\nBat: " + lastBatteryLevel +
                        "\nTS: " + timestamp;

                // Check if there are previous coordinates
                if (lastCoordinates) {
                    // Calculate the distance between the current and last coordinates
                    var distance = positionSource.position.coordinate.distanceTo(lastCoordinates);

                    // If the distance is over ten meters, update the buffer and lastCoordinates
                    if (distance > minLocationDistanceDiff) {
                        coordinateBuffer.push({
                                                  "latitude": latitude,
                                                  "longitude": longitude,
                                                  "timestamp": timestamp
                                              });
                        lastCoordinates = positionSource.position.coordinate;
                    }
                    else
                    {
                        console.log("distance diff too small "  + distance.toString());

                    }
                } else {
                    // If there are no previous coordinates, add the current coordinates to the buffer
                    console.log("no prev coords");
                    coordinateBuffer.push({
                                              "latitude": latitude,
                                              "longitude": longitude,
                                              "timestamp": timestamp
                                          });
                    lastCoordinates = positionSource.position.coordinate;
                }
            }
            else {
                gpsImage.visible = false;

            }
        }
    }

    function updateBatteryLevel()
    {
        // Get battery information, if it is available
        if (batteryInfo && batteryInfo.chargePercentage && batteryInfo.chargePercentage >= 0)
            lastBatteryLevel = batteryInfo.chargePercentage;
        else
            lastBatteryLevel = 50;
        console.log("BAT: " + batteryInfo.chargePercentage);
    }

    function startTracking()
    {
        timeri.running = !timeri.running;
        startButton.text = timeri.running ? "Stop tracking" : "Start tracking";
        if (timeri.running)
            src.start();
        else
            src.stop();
    }

    // Function to generate a random eight-digit device ID
    function generateDeviceId() {
        var deviceId = Math.floor(Math.random() * 90000000) + 10000000;
        return deviceId.toString();
    }

    // Function to get the device ID from IMEI or generate a random ID
    function getDeviceId() {
        var imeiCode = deviceInfo.imeiNumbers[0];
        if (imeiCode && imeiCode.length > 0) {
            // Use the first 8 digits of the IMEI as the device ID
            return imeiCode.substring(0, 8);
        } else {
            // Generate a random eight-digit device ID
            return generateDeviceId();
        }
    }

    function requestDeviceId()
    {
        deviceId = deviceIdSetting.value;

        // request new devId only if we did not have it in the settings
        if (!deviceId || deviceId.length === 0) {
            var url = baseUrl + "/device/";
            // Create a JSON object with IMEI
            var requestData = { "imei" : deviceInfo && deviceInfo.imeiNumbers && deviceInfo.imeiNumbers.length > 0 ? deviceInfo.imeiNumbers[0] : ""};
            // Create HTTP request
            var request = new XMLHttpRequest();
            request.open("POST", url, true);
            request.setRequestHeader("Content-Type", "application/json");
            var auth = "Bearer " + post_secret;
            request.setRequestHeader("Authorization", auth);

            // Handle response
            request.onreadystatechange = function() {
                if (request.readyState === XMLHttpRequest.DONE) {
                    if (request.status === 200 || request.status === 201) {
                        // Parse the JSON response
                        var jsonResponse = JSON.parse(request.responseText);
                        handleDeviceInfoResponse(jsonResponse);
                    } else {
                        header.text = "Error sending POST request " + request.status.toString();

                    }
                    if (!deviceId  || deviceId.length === 0) // no proper deviceId so lets generate it...
                        deviceId =  getDeviceId();
                    deviceIdText.text = "Device id: " + deviceId;
                    deviceIdSetting.value = deviceId;
                }
            };
            var jsonData = JSON.stringify(requestData);
            console.log("sending: " + jsonData);
            // Send the request with JSON data
            request.send(jsonData);
        }
        else {
            deviceIdText.text = "Device id: " +deviceId;
        }
    }

    // Function to handle the device info response
    function handleDeviceInfoResponse(responseData) {
        // Access the fields in the JSON response
        var status = responseData.status;
        var imei = responseData.imei;
        deviceId = responseData.device_id;
    }

    // Function to send GPS coordinates with POST request
    function sendLocationCoordinates() {
        console.log("coordinatebuffer length " + coordinateBuffer.length);
        if (coordinateBuffer.length < minimumCoordinatesToSend)
            return;
        // update battery level every now and then
        if (counter++ % 25 == 0)
            updateBatteryLevel();
        var batterylevelStr = "50";
        // Create JSON object
        if (lastBatteryLevel >= 0 && lastBatteryLevel <= 100)
            batterylevelStr = lastBatteryLevel.toString();
        var latitudes = "";
        var longitudes = "";
        var timeStamps = "";
        console.log("create json obj");
        // Iterate through the coordinateBuffer, perhaps stringify would do this ?
        for (var i = 0; i < coordinateBuffer.length; i++) {
            var coordinates = coordinateBuffer[i];
            if (i > 0)
            {
                latitudes += ",";
                longitudes += ",";
                timeStamps += ",";
            }
            latitudes += coordinates.latitude.toString();
            longitudes += coordinates.longitude.toString();
            timeStamps += Math.round(coordinates.timestamp).toString();
        }
        coordinateBuffer.splice(0, coordinateBuffer.length);
        var data = {
            "device_id": deviceId,
            "latitudes":latitudes,
            "longitudes": longitudes,
            "timestamps": timeStamps,
            "battery":  batterylevelStr
        };

        // Convert JSON to string
        var jsonData = JSON.stringify(data);

        // Create HTTP request
        var request = new XMLHttpRequest();
        request.open("POST", baseUrl + "/locations/", true);
        request.setRequestHeader("Content-Type", "application/json");

        var auth = "Bearer " + post_secret;
        request.setRequestHeader("Authorization", auth);

        // Handle response
        request.onreadystatechange = function() {
            if (request.readyState === XMLHttpRequest.DONE) {
                if (request.status === 200 || request.status === 201) {
                    console.log("POST request successful");
                } else {
                    header.text = "POST error: " + request.status.toString();
                    console.log("err: " + request.statusText);
                }
            }
        };
         console.log("sending: " + jsonData);
        // Send the request with JSON data
        request.send(jsonData);
    }

    // Timer to send coordinates upon firing
    Timer {
        interval: postCoordinatesInterval
        running: false
        repeat: true
        id: timeri
        onTriggered: {
            sendLocationCoordinates();
        }
    }
    // Timer to do inits when the IMEI is available or enough of tries has been tried.
    Timer {
        interval: pollImeiCodeInterval
        running: false
        repeat: false
        id: initTimer
        onTriggered: {
            initializePage();
        }
    }
}
