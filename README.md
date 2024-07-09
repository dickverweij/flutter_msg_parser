his package is a port of msg reader (javascript) wich reads and parses email messages saved in (binary) MSG format. It also reads attachments from the saved message.

## Features

It will parse the MSG file and return a data structure containing all the text, html and attachments.

## Getting started

Include this library in your Android or IOS flutter App.

## Usage

```dart
    
    Uint8List msg = await File('test/test.msg').readAsBytes();

    MsgParseResult result =  await parseMsg(msg);
  
    print (result.subject);
    print (result.from);
    print (result.recipients);
    print (result.text);
    print (result.html);
    for (final attachment in result.attachments) {
        print(attachment.name);
        print(attachment.inline);
        print(attachment.contentType);
        print(attachment.data);
        print(attachment.data64);
    }

```

## Additional information

