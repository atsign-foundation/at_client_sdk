import 'dart:io';
import 'dart:typed_data';
import 'package:at_client/at_client.dart';
import 'package:path/path.dart';
import 'test_util.dart';

void main() async {
  try {
    //1.1 put image for self
    var atsign = '@alice';
    var atClientManager = await AtClientManager.getInstance()
        .setCurrentAtSign(atsign, 'wavi', TestUtil.getAlicePreference());
    var atClient = atClientManager.atClient;
    var imageLocation = 'image.jpg'; //path to your image file
    var imageData = getdata(imageLocation);
    var metadata = Metadata()..isBinary = true;
    var atKey = AtKey()
      ..key = 'image_self'
      ..metadata = metadata;
    var result = await atClient.put(atKey, imageData);
    print(result);
    //1.2 get image for self
    var decodedImage = await atClient.get(atKey);
    saveToFile('image_retrieved_self.jpg',
        decodedImage.value); //path to save the retrieved image

    //2.1 put public image
    var publicMeta = Metadata()
      ..isPublic = true
      ..isBinary = true;
    var publicAtKey = AtKey()
      ..key = 'image_public'
      ..metadata = publicMeta;
    var publicResult = await atClient.put(publicAtKey, imageData);
    print(publicResult);
    //2.2 get public image
    var decodedPublicImage = await atClient.get(publicAtKey);
    saveToFile('image_retrieved_public.jpg', decodedPublicImage.value);

//    //3.1 share image with another atSign
//    result = await atClient.putBinary('image_shared', imageData,
//        sharedWith: '@naresh', metadata: metadata);
//    print(result);
//    //3.1 get image shared with another atSign
//    decodedImage =
//        await atClient.getBinary('image_shared', sharedWith: '@naresh');
//    saveToFile('image_retrieved_public_shared.jpg', decodedImage);
  } on Exception catch (e, trace) {
    print(e.toString());
    print(trace);
  }
}

void saveToFile(String filename, Uint8List contents) {
  var pathToFile = join(dirname(Platform.script.toFilePath()), filename);
  File(pathToFile).writeAsBytesSync(contents);
  return;
}

Uint8List getdata(String filename) {
  var pathToFile = join(dirname(Platform.script.toFilePath()), filename);
  var contents = File(pathToFile).readAsBytesSync();
  return (contents);
}
