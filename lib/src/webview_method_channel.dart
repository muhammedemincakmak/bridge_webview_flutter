// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../platform_interface.dart';

/// A [WebViewPlatformController] that uses a method channel to control the webview.
class MethodChannelWebViewPlatform implements WebViewPlatformController {
  Map<String, BridgeCallBack> _bridgeCallBackMap = Map();
  /// Constructs an instance that will listen for webviews broadcasting to the
  /// given [id], using the given [WebViewPlatformCallbacksHandler].
  MethodChannelWebViewPlatform(int id, this._platformCallbacksHandler)
      : assert(_platformCallbacksHandler != null),
        _channel = MethodChannel('plugins.flutter.io/webview_$id') {
    _channel.setMethodCallHandler(_onMethodCall);
//    _eventChannel.receiveBroadcastStream().listen((data) {
//      Map<String, dynamic> map = jsonDecode(data);
//      String name = map["name"];
//      if (name != null) {
//        BridgeCallBack callBack = _bridgeCallBackMap[name];
//        if (callBack != null) {
//          callBack(BridgeData(name, map["data"]));
//        }
//      }
//    });
  }

  final WebViewPlatformCallbacksHandler _platformCallbacksHandler;

  final MethodChannel _channel;
//  static const EventChannel _eventChannel = EventChannel("vc.xji/js_bridge");

  static const MethodChannel _cookieManagerChannel =
      MethodChannel('plugins.flutter.io/cookie_manager');

  Future<bool> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'javascriptChannelMessage':
        final String channel = call.arguments['channel'];
        final String message = call.arguments['message'];
        _platformCallbacksHandler.onJavaScriptChannelMessage(channel, message);
        return true;
      case 'navigationRequest':
        return await _platformCallbacksHandler.onNavigationRequest(
          url: call.arguments['url'],
          isForMainFrame: call.arguments['isForMainFrame'],
        );
      case 'onPageFinished':
        _platformCallbacksHandler.onPageFinished(call.arguments['url']);

      case 'onPageStarted':
        _platformCallbacksHandler.onPageStarted(call.arguments['url']);

      case 'onWebResourceError':
        _platformCallbacksHandler.onWebResourceError(
          WebResourceError(
            errorCode: call.arguments['errorCode'],
            description: call.arguments['description'],
            domain: call.arguments['domain'],
            errorType: WebResourceErrorType.values.firstWhere(
                    (WebResourceErrorType type) {
                      return type.toString() ==
                          '$WebResourceErrorType.${call.arguments['errorType']}';
                    },
                  ),
          ),
        );

      case 'bridgeCallBack':
        Map<String, dynamic> map = jsonDecode(call.arguments);
        String name = map["name"];

          BridgeCallBack callBack = _bridgeCallBackMap[name]!;
          if (callBack != null) {
            callBack(BridgeData(name, map["data"]));
          }

    }

    throw MissingPluginException(
      '${call.method} was invoked but has no handler',
    );
  }

  @override
  Future<void> loadUrl(
    String url,
    Map<String, String> headers,
  ) async {
    assert(url != null);
    return _channel.invokeMethod<void>('loadUrl', <String, dynamic>{
      'url': url,
      'headers': headers,
    });
  }

  @override
  Future<String> currentUrl() async {
    final String? url = await _channel.invokeMethod<String>('currentUrl');
    return url ?? 'default_url'; // `null` ise varsayılan bir URL döndür
  }

  @override
  Future<bool> canGoBack() async {
    final bool? canGoBack = await _channel.invokeMethod<bool>('canGoBack');
    return canGoBack ?? false; // `null` ise false döndür
  }


  @override
  Future<bool> canGoForward() async {
    final bool? canGoForward = await _channel.invokeMethod<bool>('canGoForward');
    return canGoForward ?? false; // `null` ise false döndür
  }


  @override
  Future<void> goBack() => _channel.invokeMethod<void>("goBack");

  @override
  Future<void> goForward() => _channel.invokeMethod<void>("goForward");

  @override
  Future<void> reload() => _channel.invokeMethod<void>("reload");

  @override
  Future<void> clearCache() => _channel.invokeMethod<void>("clearCache");

  @override
  Future<void> updateSettings(WebSettings settings) {
    final Map<String, dynamic> updatesMap = _webSettingsToMap(settings);
    return _channel.invokeMethod<void>('updateSettings', updatesMap);
  }

  @override
  Future<String> evaluateJavascript(String javascriptString) async {
    final String? result = await _channel.invokeMethod<String>(
        'evaluateJavascript', javascriptString);
    if (result == null) {
      throw Exception('JavaScript evaluation returned null');
    }
    return result;
  }


  @override
  Future<void> addJavascriptChannels(Set<String> javascriptChannelNames) {
    return _channel.invokeMethod<void>(
        'addJavascriptChannels', javascriptChannelNames.toList());
  }

  @override
  Future<void> removeJavascriptChannels(Set<String> javascriptChannelNames) {
    return _channel.invokeMethod<void>(
        'removeJavascriptChannels', javascriptChannelNames.toList());
  }

  @override
  Future<String> getTitle() async {
    final String? title = await _channel.invokeMethod<String>("getTitle");
    if (title == null) {
      throw Exception('Title is null');
    }
    return title;
  }


  /// Method channel implementation for [WebViewPlatform.clearCookies].
  static Future<bool> clearCookies() {
    return _cookieManagerChannel
        .invokeMethod<bool>('clearCookies')
        .then<bool>((dynamic result) => result);
  }

  static Map<String, dynamic> _webSettingsToMap(WebSettings settings) {
    final Map<String, dynamic> map = <String, dynamic>{};
    void _addIfNonNull(String key, dynamic value) {
      if (value == null) {
        return;
      }
      map[key] = value;
    }

    void _addSettingIfPresent<T>(String key, WebSetting<T> setting) {
      if (!setting.isPresent) {
        return;
      }
      map[key] = setting.value;
    }

    _addIfNonNull('jsMode', settings.javascriptMode?.index);
    _addIfNonNull('hasNavigationDelegate', settings.hasNavigationDelegate);
    _addIfNonNull('debuggingEnabled', settings.debuggingEnabled);
    _addIfNonNull(
        'gestureNavigationEnabled', settings.gestureNavigationEnabled);
    _addSettingIfPresent('userAgent', settings.userAgent);
    return map;
  }

  /// Converts a [CreationParams] object to a map as expected by `platform_views` channel.
  ///
  /// This is used for the `creationParams` argument of the platform views created by
  /// [AndroidWebViewBuilder] and [CupertinoWebViewBuilder].
  static Map<String, dynamic> creationParamsToMap(
      CreationParams creationParams) {
    return <String, dynamic>{
      'initialUrl': creationParams.initialUrl,
      'settings': _webSettingsToMap(creationParams.webSettings),
      'javascriptChannelNames': creationParams.javascriptChannelNames.toList(),
      'userAgent': creationParams.userAgent,
      'autoMediaPlaybackPolicy': creationParams.autoMediaPlaybackPolicy.index,
    };
  }

  @override
  Future<void> callHandler(String name, {dynamic data, BridgeCallBack? onCallBack}) {
    if (onCallBack != null) {
      _bridgeCallBackMap[name] = onCallBack;
    }
    return _channel.invokeMethod("callHandler", {"name": name, "data": data});
  }

  @override
  Future<void> registerHandler(String name, {dynamic response, BridgeCallBack? onCallBack}) {
    if (onCallBack != null) {
      _bridgeCallBackMap[name] = onCallBack;
    }
    return _channel.invokeMethod("registerHandler", {"name": name, "response": response});
  }
}
