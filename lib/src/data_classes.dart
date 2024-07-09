import 'dart:typed_data';

class MsgEmailAttachment {
  final String id;
  final String name;
  final String contentType;
  final bool inline;
  final Uint8List data;
  final String data64;

  MsgEmailAttachment({
    required this.id,
    required this.name,
    required this.contentType,
    required this.inline,
    required this.data,
    required this.data64,
  });
}

class MsgEmailAddress {
  final String name;
  final String email;

  MsgEmailAddress({
    required this.name,
    required this.email,
  });
}

class MsgEmailHeader {
  final String name;
  final String value;

  MsgEmailHeader({
    required this.name,
    required this.value,
  });
}

class MsgParseResult {
  final DateTime date;
  final String subject;
  final String? from;
  final List<MsgEmailAddress>? recipients;
  final String? text;
  final String? html;
  final List<MsgEmailAttachment>? attachments;

  MsgParseResult({
    required this.date,
    required this.subject,
    this.from,
    this.recipients,
    this.text,
    this.html,
    this.attachments,
  });
}
