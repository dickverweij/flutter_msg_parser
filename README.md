This package enabled the parsing of binary MSG files

## Features

It will parse the MSG file and return a datastructure containing all the text, html and attachments.

## Getting started

Include this library in your Android or IOS flutter App. You could also use it on other dart platforms as it has no external dependancies.

## Usage

```dart
    
    Uint8List msg = await File('test/test.mg').readAsBytes();

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

