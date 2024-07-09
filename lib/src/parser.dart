// ignore_for_file: non_constant_identifier_names

import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_convert/enough_convert.dart';
import 'package:flutter_msg_parser/src/data_classes.dart';

/// Parse Micorsoft Mail Message (Outlook) MSG binary file from [data] byte array
/// Returns typed [MsgParseResult] containing the
/// message fields and attachments inside the message
MsgParseResult parseMsg(Uint8List data) {
  final byteData = data.buffer.asByteData();

  if (!_isMSGFile(byteData)) {
    throw Exception('Not a MSG file');
  }

  final result = _parseMsgData(byteData);
  final attachments = (result['fieldsData']['attachments'] as List)
      .cast<Map<dynamic, dynamic>>()
      .map((e) {
    bool inline = e.containsKey('pidContentId');
    Uint8List data = _getAttachmentData(result, byteData, e['dataId']);
    return MsgEmailAttachment(
      id: inline ? e['pidContentId'].toString() : e['dataId'].toString(),
      name: e['name'],
      inline: inline,
      contentType: inline ? e['mimeType'] : '',
      data: data,
      data64: base64Encode(data),
    );
  }).toList();

  if (result['fieldsData']['rtfBody'] != null) {
    result['fieldsData']['bodyHTML'] = _rtfToHtml(
      result['fieldsData']['rtfBody'],
    );
  }

  return MsgParseResult(
    date: DateTime.now(),
    subject: result['fieldsData']['subject'],
    from: result['fieldsData']['senderName'],
    recipients: (result['fieldsData']['recipients'] as List)
        .map((e) => MsgEmailAddress(name: e['name'], email: e['email']))
        .toList(),
    text: result['fieldsData']['body'],
    html: result['fieldsData']['bodyHTML'],
    attachments: attachments,
  );
}

typedef MsgInnerHeader = ({
  int PROPERTY_START_OFFSET,
  int BAT_START_OFFSET,
  int BAT_COUNT_OFFSET,
  int SBAT_START_OFFSET,
  int SBAT_COUNT_OFFSET,
  int XBAT_START_OFFSET,
  int XBAT_COUNT_OFFSET,
});

typedef MsgInnerTypeEnum = ({
  int DIRECTORY,
  int DOCUMENT,
  int ROOT,
});

typedef MsgInnerProperty = ({
  int NO_INDEX,
  int PROPERTY_SIZE,
  int NAME_SIZE_OFFSET,
  int MAX_NAME_LENGTH,
  int TYPE_OFFSET,
  int PREVIOUS_PROPERTY_OFFSET,
  int NEXT_PROPERTY_OFFSET,
  int CHILD_PROPERTY_OFFSET,
  int START_BLOCK_OFFSET,
  int SIZE_OFFSET,
  MsgInnerTypeEnum TYPE_ENUM,
});

typedef MsgInnerField = ({
  Map<String, String> PREFIX,
  Map<String, String> NAME_MAPPING,
  Map<String, String> CLASS_MAPPING,
  Map<String, String> TYPE_MAPPING,
  Map<String, String> DIR_TYPE,
});

typedef MsgInnerConstants = ({
  int UNUSED_BLOCK,
  int END_OF_CHAIN,
  int S_BIG_BLOCK_SIZE,
  int S_BIG_BLOCK_MARK,
  int L_BIG_BLOCK_SIZE,
  int L_BIG_BLOCK_MARK,
  int SMALL_BLOCK_SIZE,
  int BIG_BLOCK_MIN_DOC_SIZE,
  MsgInnerHeader HEADER,
  MsgInnerProperty PROP,
  MsgInnerField FIELD,
});

typedef MsgConstants = ({
  List<int> FILE_HEADER,
  MsgInnerConstants MSG,
});

/// Constants used in the parser
var _constants = (
  FILE_HEADER: _uInt2int([
    0xD0,
    0xCF,
    0x11,
    0xE0,
    0xA1,
    0xB1,
    0x1A,
    0xE1,
  ]),
  MSG: (
    UNUSED_BLOCK: -1,
    END_OF_CHAIN: -2,
    S_BIG_BLOCK_SIZE: 0x0200,
    S_BIG_BLOCK_MARK: 9,
    L_BIG_BLOCK_SIZE: 0x1000,
    L_BIG_BLOCK_MARK: 12,
    SMALL_BLOCK_SIZE: 0x0040,
    BIG_BLOCK_MIN_DOC_SIZE: 0x1000,
    HEADER: (
      PROPERTY_START_OFFSET: 0x30,
      BAT_START_OFFSET: 0x4c,
      BAT_COUNT_OFFSET: 0x2C,
      SBAT_START_OFFSET: 0x3C,
      SBAT_COUNT_OFFSET: 0x40,
      XBAT_START_OFFSET: 0x44,
      XBAT_COUNT_OFFSET: 0x48,
    ),
    PROP: (
      NO_INDEX: -1,
      PROPERTY_SIZE: 0x0080,
      NAME_SIZE_OFFSET: 0x40,
      MAX_NAME_LENGTH: (/*NAME_SIZE_OFFSET*/ 0x40 / 2) - 1,
      TYPE_OFFSET: 0x42,
      PREVIOUS_PROPERTY_OFFSET: 0x44,
      NEXT_PROPERTY_OFFSET: 0x48,
      CHILD_PROPERTY_OFFSET: 0x4C,
      START_BLOCK_OFFSET: 0x74,
      SIZE_OFFSET: 0x78,
      TYPE_ENUM: (
        DIRECTORY: 1,
        DOCUMENT: 2,
        ROOT: 5,
      )
    ),
    FIELD: (
      PREFIX: (
        ATTACHMENT: '__attach_version1.0',
        RECIPIENT: '__recip_version1.0',
        DOCUMENT: '__substg1.',
      ),
      NAME_MAPPING: {
        '0037': 'subject',
        '0c1a': 'senderName',
        '5d02': 'senderEmail',
        '1000': 'body',
        '1013': 'bodyHTML',
        '1009': 'rtfBody',
        '007d': 'headers',
        '3703': 'extension',
        '3704': 'fileNameShort',
        '3707': 'fileName',
        '3712': 'pidContentId',
        '370e': 'mimeType',
        '3001': 'name',
        '39fe': 'email',
      },
      CLASS_MAPPING: {
        'ATTACHMENT_DATA': '3701',
      },
      TYPE_MAPPING: {
        '001e': 'string',
        '001f': 'unicode',
        '0102': 'binary',
      },
      DIR_TYPE: {
        'INNER_MSG': '000d',
      }
    )
  ),
);

// poor mans rtf to html converter
String _rtfToHtml(String rtf) {
  String html = '';
  String rtfStripped = rtf.replaceAll(RegExp('\\\\htmlrtf.+\\\\htmlrtf0'), '');
  rtfStripped = rtfStripped.replaceAll(RegExp('\\\\htmlrtf.+'), '');
  rtfStripped = rtfStripped.replaceAll(RegExp('\\\\htmlrtf0'), '');
  rtfStripped = rtfStripped.replaceAll('{\\*\\htmltag64}', '');
  rtfStripped = rtfStripped.replaceAll('{\\*\\htmltag72}', '');

  final regEx =
      RegExp('^{\\\\\\*\\\\htmltag[0-9]+[ ]?(.+)}([^}{]*)\$', multiLine: true);
  regEx.allMatches(rtfStripped).forEach((match) {
    if (match.group(1) != null) {
      html += match.group(1)!;
    }
    if (match.group(2) != null) {
      html += match.group(2)!;
    }
  });

  // remove trailing '}' and newline char
  return html.substring(0, html.length - 1);
}

List<int> _uInt2int(data) {
  var result = List<int>.filled(data.length, 0);
  for (var i = 0; i < data.length; i++) {
    result[i] = (data[i] << 24) >> 24;
  }
  return result;
}

Uint8List _getAttachmentData(
  Map<String, dynamic> result,
  ByteData bytedata,
  dataId,
) {
  if (result["propertyData"] == null) {
    return Uint8List(0);
  }
  var fieldProperty = result["propertyData"][dataId];
  String fieldTypeMapped =
      _constants.MSG.FIELD.TYPE_MAPPING[_getFieldType(fieldProperty)]!;
  var fieldData = _getFieldValue(
    bytedata,
    result,
    fieldProperty,
    fieldTypeMapped,
  );

  return fieldData;
}

bool _isMSGFile(ByteData byteData) {
  for (var i = 0; i < _constants.FILE_HEADER.length; i++) {
    if (byteData.getUint8(i) != _constants.FILE_HEADER[i]) {
      return false;
    }
  }
  return true;
}

Map<String, dynamic> _headerData(ByteData byteData) {
  var headerData = <String, dynamic>{};

  // system data
  headerData["bigBlockSize"] =
      byteData.getInt8(30) == _constants.MSG.L_BIG_BLOCK_MARK
          ? _constants.MSG.L_BIG_BLOCK_SIZE
          : _constants.MSG.S_BIG_BLOCK_SIZE;

  headerData["bigBlockLength"] = (headerData["bigBlockSize"] / 4).floor();
  headerData["xBlockLength"] = headerData["bigBlockLength"] - 1;

  // header data
  headerData["batCount"] =
      byteData.getInt32(_constants.MSG.HEADER.BAT_COUNT_OFFSET, Endian.little);
  headerData["propertyStart"] = byteData.getInt32(
      _constants.MSG.HEADER.PROPERTY_START_OFFSET, Endian.little);
  headerData["sbatStart"] =
      byteData.getInt32(_constants.MSG.HEADER.SBAT_START_OFFSET, Endian.little);
  headerData["sbatCount"] =
      byteData.getInt32(_constants.MSG.HEADER.SBAT_COUNT_OFFSET, Endian.little);
  headerData["xbatStart"] =
      byteData.getInt32(_constants.MSG.HEADER.XBAT_START_OFFSET, Endian.little);
  headerData["xbatCount"] =
      byteData.getInt32(_constants.MSG.HEADER.XBAT_COUNT_OFFSET, Endian.little);

  return headerData;
}

Map<String, dynamic> _parseMsgData(ByteData byteData) {
  var msgData = _headerData(byteData);
  msgData["batData"] = _batData(byteData, msgData);
  msgData["sbatData"] = _sbatData(byteData, msgData);

  if (msgData['xbatCount'] > 0) {
    _xbatData(byteData, msgData);
  }

  msgData["propertyData"] = _propertyData(byteData, msgData);
  msgData["fieldsData"] = _fieldsData(byteData, msgData);
  return msgData;
}

int _batCountInHeader(Map<String, dynamic> msgData) {
  var maxBatsInHeader = (_constants.MSG.S_BIG_BLOCK_SIZE -
          _constants.MSG.HEADER.BAT_START_OFFSET) /
      4;
  return (msgData['batCount'] < maxBatsInHeader)
      ? msgData['batCount']
      : maxBatsInHeader;
}

List<int> _batData(
  ByteData byteData,
  Map<String, dynamic> msgData,
) {
  var result = List<int>.filled(_batCountInHeader(msgData), 0);
  int position = _constants.MSG.HEADER.BAT_START_OFFSET;
  for (var i = 0; i < result.length; i++) {
    result[i] = byteData.getInt32(position, Endian.little);
    position += 4;
  }
  return result;
}

int _getBlockOffsetAt(
  Map<String, dynamic> msgData,
  int offset,
) {
  return (offset + 1) * (msgData['bigBlockSize'] as int);
}

List<int> _getBlockAt(
  ByteData byteData,
  Map<String, dynamic> msgData,
  int offset,
) {
  var startOffset = _getBlockOffsetAt(msgData, offset);
  var len = msgData['bigBlockLength'];
  List<int> result = [];

  for (var i = 0; i < len; i++) {
    result.add(byteData.getInt32(startOffset, Endian.little));
    startOffset += 4;
  }

  return result;
}

int _getNextBlockInner(
  ByteData byteData,
  Map<String, dynamic> msgData,
  int offset,
  blockOffsetData,
) {
  var currentBlock = (offset / (msgData['bigBlockLength'] as int)).floor();
  var currentBlockIndex = offset % (msgData['bigBlockLength'] as int);

  var startBlockOffset = blockOffsetData[currentBlock];

  return _getBlockAt(byteData, msgData, startBlockOffset)[currentBlockIndex];
}

int _getNextBlock(
  ByteData byteData,
  Map<String, dynamic> msgData,
  int offset,
) {
  return _getNextBlockInner(byteData, msgData, offset, msgData['batData']);
}

int _getNextBlockSmall(
  ByteData byteData,
  Map<String, dynamic> msgData,
  offset,
) {
  return _getNextBlockInner(byteData, msgData, offset, msgData['sbatData']);
}

List<int> _sbatData(
  ByteData byteData,
  Map<String, dynamic> msgData,
) {
  final result = <int>[];
  var startIndex = msgData['sbatStart'];

  for (var i = 0;
      i < msgData['sbatCount'] && startIndex != _constants.MSG.END_OF_CHAIN;
      i++) {
    result.add(startIndex);
    startIndex = _getNextBlock(
      byteData,
      msgData,
      startIndex,
    );
  }
  return result;
}

void _xbatData(
  ByteData byteData,
  Map<String, dynamic> msgData,
) {
  var batCount = _batCountInHeader(msgData);
  var batCountTotal = msgData['batCount'];
  var remainingBlocks = batCountTotal - batCount;

  var nextBlockAt = msgData['xbatStart'];
  for (var i = 0; i < msgData['xbatCount']; i++) {
    var xBatBlock = _getBlockAt(
      byteData,
      msgData,
      nextBlockAt,
    );
    nextBlockAt = xBatBlock[msgData['xBlockLength']];

    var blocksToProcess = (remainingBlocks < msgData['xBlockLength'])
        ? remainingBlocks
        : msgData['xBlockLength'];
    for (var j = 0; j < blocksToProcess; j++) {
      var blockStartAt = xBatBlock[j];
      if (blockStartAt == _constants.MSG.UNUSED_BLOCK ||
          blockStartAt == _constants.MSG.END_OF_CHAIN) {
        break;
      }
      msgData['batData'].add(blockStartAt);
    }
    remainingBlocks -= blocksToProcess;
  }
}

List<Map<String, dynamic>?> _propertyData(
  ByteData byteData,
  Map<String, dynamic> msgData,
) {
  final props = <Map<String, dynamic>?>[];

  var currentOffset = msgData['propertyStart'];

  while (currentOffset != _constants.MSG.END_OF_CHAIN) {
    _convertBlockToProperties(
      byteData,
      msgData,
      currentOffset,
      props,
    );
    currentOffset = _getNextBlock(
      byteData,
      msgData,
      currentOffset,
    );
  }
  if (props.isNotEmpty && props[0] != null) {
    _createPropertyHierarchy(props, props[0]!);
  }
  return props;
}

String _convertName(
  ByteData byteData,
  int offset,
) {
  final nameLength = byteData.getInt16(
      offset + (_constants.MSG.PROP.NAME_SIZE_OFFSET), Endian.little);
  if (nameLength < 1) {
    return '';
  } else {
    return _readStringAt(byteData, offset, nameLength ~/ 2);
  }
}

String _readStringAt(
  ByteData byteData,
  int offset,
  length,
) {
  var result = '';
  for (var i = 0; i < length; i++) {
    result +=
        String.fromCharCode(byteData.getInt16(offset + i * 2, Endian.little));
  }
  return result;
}

String _readUcsStringAt(
  ByteData byteData,
  int offset,
  length,
) {
  var result = '';
  for (var i = 0; i < length; i++) {
    result +=
        String.fromCharCode(byteData.getInt16(offset + i * 2, Endian.little));
  }
  return result;
}

Uint8List _readUint8listAt(
  ByteData byteData,
  int offset,
  length,
) {
  return Uint8List(length)
    ..setRange(0, length, byteData.buffer.asUint8List(offset, length));
}

Map<String, dynamic> _convertProperty(
  ByteData byteData,
  index,
  int offset,
) {
  return {
    'index': index,
    'type': byteData.getInt8(offset + (_constants.MSG.PROP.TYPE_OFFSET)),
    'name': _convertName(byteData, offset),
    'previousProperty': byteData.getInt32(
        offset + (_constants.MSG.PROP.PREVIOUS_PROPERTY_OFFSET), Endian.little),
    'nextProperty': byteData.getInt32(
        offset + (_constants.MSG.PROP.NEXT_PROPERTY_OFFSET), Endian.little),
    'childProperty': byteData.getInt32(
        offset + (_constants.MSG.PROP.CHILD_PROPERTY_OFFSET), Endian.little),
    'startBlock': byteData.getInt32(
        offset + (_constants.MSG.PROP.START_BLOCK_OFFSET), Endian.little),
    'sizeBlock': byteData.getInt32(
        offset + (_constants.MSG.PROP.SIZE_OFFSET), Endian.little)
  };
}

void _convertBlockToProperties(
  ByteData byteData,
  Map<String, dynamic> msgData,
  propertyBlockOffset,
  props,
) {
  var propertyCount =
      msgData['bigBlockSize'] ~/ _constants.MSG.PROP.PROPERTY_SIZE;
  var propertyOffset = _getBlockOffsetAt(msgData, propertyBlockOffset);

  for (var i = 0; i < propertyCount; i++) {
    var propertyType =
        byteData.getInt8(propertyOffset + _constants.MSG.PROP.TYPE_OFFSET);

    if (propertyType == _constants.MSG.PROP.TYPE_ENUM.ROOT ||
        propertyType == _constants.MSG.PROP.TYPE_ENUM.DIRECTORY ||
        propertyType == _constants.MSG.PROP.TYPE_ENUM.DOCUMENT) {
      props.add(_convertProperty(byteData, props.length, propertyOffset));
    } else {
      /* unknown property types */
      props.add(<String, dynamic>{});
    }

    propertyOffset += _constants.MSG.PROP.PROPERTY_SIZE;
  }
}

void _createPropertyHierarchy(
  List<Map<String, dynamic>?> props,
  Map<String, dynamic> nodeProperty,
) {
  if (nodeProperty['childProperty'] == _constants.MSG.PROP.NO_INDEX) {
    return;
  }
  nodeProperty['children'] = [];

  var children = [nodeProperty['childProperty']];
  while (children.isNotEmpty) {
    var currentIndex = children.removeAt(0);
    var current = props[currentIndex];
    if (current == null) {
      continue;
    }
    nodeProperty['children'].add(currentIndex);

    if (current['type'] == _constants.MSG.PROP.TYPE_ENUM.DIRECTORY) {
      _createPropertyHierarchy(props, current);
    }
    if (current['previousProperty'] != _constants.MSG.PROP.NO_INDEX) {
      children.add(current['previousProperty']);
    }
    if (current['nextProperty'] != _constants.MSG.PROP.NO_INDEX) {
      children.add(current['nextProperty']);
    }
  }
}

Map<String, dynamic> _fieldsData(
  ByteData byteData,
  Map<String, dynamic> msgData,
) {
  var fields = <String, dynamic>{'attachments': [], 'recipients': []};
  _fieldsDataDir(
    byteData,
    msgData,
    msgData['propertyData'][0],
    fields,
  );
  return fields;
}

void _fieldsDataDir(
  ByteData byteData,
  Map<String, dynamic> msgData,
  Map<String, dynamic> dirProperty,
  Map<String, dynamic> fields,
) {
  if (dirProperty['children'] != null && dirProperty['children'].length > 0) {
    for (var i = 0; i < dirProperty['children'].length; i++) {
      var childProperty = msgData['propertyData'][dirProperty['children'][i]];

      if (childProperty['type'] == _constants.MSG.PROP.TYPE_ENUM.DIRECTORY) {
        _fieldsDataDirInner(
          byteData,
          msgData,
          childProperty,
          fields,
        );
      } else if (childProperty['type'] ==
              _constants.MSG.PROP.TYPE_ENUM.DOCUMENT &&
          childProperty['name'].indexOf(_constants.MSG.FIELD.PREFIX.DOCUMENT) ==
              0) {
        _fieldsDataDocument(
          byteData,
          msgData,
          childProperty,
          fields,
        );
      }
    }
  }
}

void _fieldsDataDirInner(
  ByteData byteData,
  Map<String, dynamic> msgData,
  Map<String, dynamic> dirProperty,
  Map<String, dynamic> fields,
) {
  if (dirProperty['name'].indexOf(_constants.MSG.FIELD.PREFIX.ATTACHMENT) ==
      0) {
    var attachmentField = <String, dynamic>{};
    fields['attachments'].add(attachmentField);
    _fieldsDataDir(
      byteData,
      msgData,
      dirProperty,
      attachmentField,
    );
  } else if (dirProperty['name']
          .indexOf(_constants.MSG.FIELD.PREFIX.RECIPIENT) ==
      0) {
    var recipientField = <String, dynamic>{};
    fields['recipients'].add(recipientField);
    _fieldsDataDir(
      byteData,
      msgData,
      dirProperty,
      recipientField,
    );
  } else {
    final childFieldType = _getFieldType(dirProperty);
    if (childFieldType != _constants.MSG.FIELD.DIR_TYPE['INNER_MSG']) {
      _fieldsDataDir(
        byteData,
        msgData,
        dirProperty,
        fields,
      );
    } else {
      fields['innerMsgContent'] = true;
    }
  }
}

bool _isAddPropertyValue(
  String fieldName,
  String fieldTypeMapped,
) {
  return fieldName != 'body' || fieldTypeMapped != 'binary';
}

void _fieldsDataDocument(
  ByteData byteData,
  Map<String, dynamic> msgData,
  Map<String, dynamic> documentProperty,
  Map<String, dynamic> fields,
) {
  var name = documentProperty['name'] as String? ?? '';

  if (name.length < 12) {
    return;
  }

  var value = name.substring(12).toLowerCase();
  var fieldClass = value.substring(0, 4);
  var fieldType = value.substring(4, 8);

  String? fieldName = _constants.MSG.FIELD.NAME_MAPPING[fieldClass];
  var fieldTypeMapped = _constants.MSG.FIELD.TYPE_MAPPING[fieldType];

  if (fieldName != null && fieldTypeMapped != null) {
    var fieldValue = _getFieldValue(
      byteData,
      msgData,
      documentProperty,
      fieldTypeMapped,
    );

    if (_isAddPropertyValue(fieldName, fieldTypeMapped)) {
      fields[fieldName] = _applyValueConverter(
        fieldName,
        fieldTypeMapped,
        fieldValue,
      );
    }

    if (fieldClass == '1009' && fieldTypeMapped == 'binary') {
      fields[fieldName] = _decompressRTF(fieldValue);
    }
  }
  if (fieldClass == _constants.MSG.FIELD.CLASS_MAPPING['ATTACHMENT_DATA']) {
    fields['dataId'] = documentProperty['index'];
    fields['contentLength'] = documentProperty['sizeBlock'];
  }
}

String _decompressRTF(Uint8List src) {
  String prebuf =
      "{\\rtf1\\ansi\\mac\\deff0\\deftab720{\\fonttbl;}{\\f0\\fnil \\froman \\fswiss \\fmodern \\fscript \\fdecor MS Sans SerifSymbolArialTimes New RomanCourier{\\colortbl\\red0\\green0\\blue0\n\r\\par \\pard\\plain\\f0\\fs20\\b\\i\\u\\tab\\tx";

  const codec = Windows1252Codec(allowInvalid: false);
  int MAGIC_COMPRESSED = 0x75465a4c, MAGIC_UNCOMPRESSED = 0x414c454d;
  Uint8List dst;
  int inPos = 0; // current position in src array
  int outPos = 0; // current position in dst array

  // get header fields
  if (src.length < 16) {
    return '';
  }

  ByteData input = src.buffer.asByteData();

  int compressedSize = input.getUint32(inPos, Endian.little);
  inPos += 4;
  int uncompressedSize = input.getUint32(inPos, Endian.little);
  inPos += 4;
  int magic = input.getUint32(inPos, Endian.little);
  inPos += 4;
  // note: CRC must be validated only for compressed data (and includes padding)
  //int crc32 = input.getUint32(inPos, Endian.little);
  inPos += 4;

  if (compressedSize != src.length - 4) {
    return '';
  }

  // process the data
  if (magic == MAGIC_UNCOMPRESSED) {
    return codec.decode(input.buffer.asUint8List().sublist(16));
  } else if (magic == MAGIC_COMPRESSED) {
    outPos = prebuf.length;
    dst = Uint8List(uncompressedSize + prebuf.length);

    dst.setRange(0, outPos, codec.encode(prebuf), 0);

    int flagCount = 0;
    int flags = 0;
    try {
      while (true) {
        // each flag byte controls 8 literals/references, 1 per bit
        // each bit is 1 for reference, 0 for literal
        flags = ((flagCount++ & 7) == 0) ? src[inPos++] : flags >> 1;
        if ((flags & 1) == 0) {
          dst[outPos++] = src[inPos++]; // copy literal
        } else {
          // read reference: 12-bit offset (from block start) and 4-bit length
          int offset = src[inPos++] & 0xFF;
          int length = src[inPos++] & 0xFF;
          offset =
              (offset << 4) | (length >>> 4); // the offset from block start
          length = (length & 0xF) + 2; // the number of bytes to copy
          // the decompression buffer is supposed to wrap around back
          // to the beginning when the end is reached. we save the
          // need for such a buffer by pointing straight into the data
          // buffer, and simulating this behaviour by modifying the
          // pointers appropriately.
          offset = outPos & 0xFFFFF000 | offset; // the absolute offset in array
          if (offset >= outPos) {
            if (offset == outPos) {
              break; // a self-reference marks the end of data
            }
            offset -= 4096; // take from previous block
          }
          // note: can't use System.arraycopy, because the referenced
          // bytes can cross through the current out position.
          int end = offset + length;
          while (offset < end) {
            dst[outPos++] = dst[offset++];
          }
        }
      }
    } catch (e) {
      return '';
    }
    // copy it back without the prebuffered data
    src = dst;
    dst = Uint8List(uncompressedSize);
    dst.setRange(0, uncompressedSize, src, prebuf.length);

    return codec.decode(dst);
  } else {
    // unknown magic number
    return '';
  }
}

dynamic _applyValueConverter(
  String fieldName,
  String fieldTypeMapped,
  fieldValue,
) {
  if (fieldTypeMapped == 'binary' && fieldName == 'bodyHTML') {
    return _convertUint8ArrayToString(fieldValue);
  }
  return fieldValue;
}

String _getFieldType(Map<String, dynamic> fieldProperty) {
  var value = fieldProperty['name'].substring(12).toLowerCase();
  return value.substring(4, 8);
}

// extractor structure to manage bat/sbat block types and different data types
var _extractorFieldValue = {
  'sbat': {
    'extractor': (
      ByteData byteData,
      msgData,
      fieldProperty,
      dataTypeExtractor,
    ) {
      var chain = _getChainByBlockSmall(
        byteData,
        msgData,
        fieldProperty,
      );
      if (chain.length == 1) {
        return _readDataByBlockSmall(
          byteData,
          msgData,
          fieldProperty['startBlock'],
          fieldProperty['sizeBlock'],
          dataTypeExtractor,
        );
      } else if (chain.length > 1) {
        return _readChainDataByBlockSmall(
          byteData,
          msgData,
          fieldProperty,
          chain,
          dataTypeExtractor,
        );
      }
      return null;
    },
    'dataType': {
      'string': (
        ByteData byteData,
        msgData,
        blockStartOffset,
        bigBlockOffset,
        blockSize,
      ) {
        return _readStringAt(
          byteData,
          blockStartOffset + bigBlockOffset,
          blockSize,
        );
      },
      'unicode': (
        ByteData byteData,
        msgData,
        blockStartOffset,
        bigBlockOffset,
        blockSize,
      ) {
        return _readUcsStringAt(
          byteData,
          blockStartOffset + bigBlockOffset,
          blockSize ~/ 2,
        );
      },
      'binary': (
        ByteData byteData,
        msgData,
        blockStartOffset,
        bigBlockOffset,
        blockSize,
      ) {
        return _readUint8listAt(
          byteData,
          blockStartOffset + bigBlockOffset,
          blockSize,
        );
      }
    }
  },
  'bat': {
    'extractor':
        (ByteData byteData, msgData, fieldProperty, dataTypeExtractor) {
      var offset = _getBlockOffsetAt(
        msgData,
        fieldProperty['startBlock'],
      );

      return dataTypeExtractor(byteData, offset, fieldProperty);
    },
    'dataType': {
      'string': (ByteData byteData, offset, fieldProperty) {
        return _readStringAt(
          byteData,
          offset,
          fieldProperty['sizeBlock'],
        );
      },
      'unicode': (ByteData byteData, offset, fieldProperty) {
        return _readUcsStringAt(
          byteData,
          offset,
          fieldProperty['sizeBlock'] ~/ 2,
        );
      },
      'binary': (ByteData byteData, offset, fieldProperty) {
        return _readUint8listAt(
          byteData,
          offset,
          fieldProperty['sizeBlock'],
        );
      }
    }
  }
};

_readDataByBlockSmall(
  ByteData byteData,
  Map<String, dynamic> msgData,
  int startBlock,
  int blockSize,
  dataTypeExtractor,
) {
  var byteOffset = startBlock * _constants.MSG.SMALL_BLOCK_SIZE;
  var bigBlockNumber = (byteOffset / msgData['bigBlockSize']).floor();
  var bigBlockOffset = byteOffset % msgData['bigBlockSize'];
  var rootProp = msgData['propertyData'][0];
  var nextBlock = rootProp['startBlock'];
  for (var i = 0; i < bigBlockNumber; i++) {
    nextBlock = _getNextBlock(byteData, msgData, nextBlock);
  }
  var blockStartOffset = _getBlockOffsetAt(msgData, nextBlock);
  return dataTypeExtractor(
    byteData,
    msgData,
    blockStartOffset,
    bigBlockOffset,
    blockSize,
  );
}

_readChainDataByBlockSmall(
  ByteData byteData,
  Map<String, dynamic> msgData,
  Map<String, dynamic> fieldProperty,
  chain,
  dataTypeExtractor,
) {
  var resultData = Uint8List(fieldProperty['sizeBlock']);
  for (var i = 0, idx = 0; i < chain.length; i++) {
    var data = _readDataByBlockSmall(
        byteData,
        msgData,
        chain[i],
        _constants.MSG.SMALL_BLOCK_SIZE,
        (_extractorFieldValue['sbat']?['dataType'] as Map)['binary']);
    for (var j = 0; j < data.length; j++) {
      if (idx < fieldProperty['sizeBlock']) {
        resultData[idx++] = data[j];
      }
    }
  }

  return dataTypeExtractor(
    resultData.buffer.asByteData(),
    msgData,
    0,
    0,
    fieldProperty['sizeBlock'],
  );
}

List<dynamic> _getChainByBlockSmall(
  ByteData byteData,
  Map<String, dynamic> msgData,
  Map<String, dynamic> fieldProperty,
) {
  var blockChain = [];
  var nextBlockSmall = fieldProperty['startBlock'];
  while (nextBlockSmall != _constants.MSG.END_OF_CHAIN) {
    blockChain.add(nextBlockSmall);
    nextBlockSmall = _getNextBlockSmall(
      byteData,
      msgData,
      nextBlockSmall,
    );
  }
  return blockChain;
}

_getFieldValue(
  ByteData byteData,
  Map<String, dynamic> msgData,
  Map<String, dynamic> fieldProperty,
  String typeMapped,
) {
  dynamic value;
  var valueExtractor =
      fieldProperty['sizeBlock'] < _constants.MSG.BIG_BLOCK_MIN_DOC_SIZE
          ? _extractorFieldValue['sbat']
          : _extractorFieldValue['bat'];
  var dataTypeExtractor = (valueExtractor?['dataType'] as Map)[typeMapped];
  if (dataTypeExtractor != null) {
    value = (valueExtractor?['extractor'] as Function?)?.call(
      byteData,
      msgData,
      fieldProperty,
      dataTypeExtractor,
    );
  }
  return value;
}

String _convertUint8ArrayToString(uint8ArraValue) {
  try {
    const codec = Windows1252Codec(allowInvalid: false);
    return codec.decode(uint8ArraValue);
  } catch (e) {
    return '';
  }
}
