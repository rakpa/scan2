import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:permission_handler_platform_interface/permission_handler_platform_interface.dart';
import 'package:scan2/core/permissions/camera_permission.dart';
import 'package:scan2/features/camera/domain/native_document_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePermissions permissions;

  setUp(() {
    NativeDocumentScanner.debugReset();
    CameraPermission.debugPollInterval(Duration.zero);
    permissions = _FakePermissions();
    PermissionHandlerPlatform.instance = permissions;
  });

  tearDown(NativeDocumentScanner.debugReset);

  test('one in-flight camera prompt is shared by concurrent callers', () async {
    permissions.block = Completer<void>();

    final first = CameraPermission.ensureGranted();
    final second = CameraPermission.ensureGranted();
    await Future<void>.delayed(Duration.zero);

    expect(permissions.requests, 1);
    permissions.block!.complete();

    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(permissions.requests, 1);
  });

  test('already-requesting is waited out instead of crashing', () async {
    permissions.throwAlreadyOnRequest = true;
    permissions.grantAfterRequestAttempt = true;

    expect(await CameraPermission.ensureGranted(), isTrue);
  });

  test('permanently denied does not open a second prompt', () async {
    permissions.status = PermissionStatus.permanentlyDenied;

    expect(await CameraPermission.ensureGranted(), isFalse);
    expect(permissions.requests, 0);
  });

  test('scanner error copy never dumps the plugin exception', () {
    final already = PlatformException(
      code: CameraPermission.alreadyRequestingCode,
      message:
          'A request for permissions is already running, please wait for it '
          'to finish before doing another request (note that you can request '
          'multiple permissions at the same time).',
    );

    expect(
      CameraPermission.describeError(already),
      'The camera is still asking for permission. Tap Try again.',
    );
    expect(
      CameraPermission.describeError(already).contains('PlatformException'),
      isFalse,
    );
    expect(
      CameraPermission.describeError(const CameraAccessDenied()),
      contains('camera access'),
    );
  });

  test('native scanner asks for camera once then opens VisionKit', () async {
    permissions.status = PermissionStatus.granted;
    var scans = 0;
    const channel = MethodChannel('cunning_document_scanner');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          scans++;
          expect(call.method, 'getPictures');
          return <String>['/tmp/page.png'];
        });

    const scanner = NativeDocumentScanner();
    final pages = await Future.wait([scanner.scan(), scanner.scan()]);

    expect(scans, 1);
    expect(pages[0], ['/tmp/page.png']);
    expect(pages[1], ['/tmp/page.png']);
    expect(permissions.requests, 0);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}

class _FakePermissions extends PermissionHandlerPlatform {
  PermissionStatus status = PermissionStatus.denied;
  int requests = 0;
  Completer<void>? block;
  bool throwAlreadyOnRequest = false;
  bool grantAfterRequestAttempt = false;

  @override
  Future<PermissionStatus> checkPermissionStatus(Permission permission) async {
    return status;
  }

  @override
  Future<ServiceStatus> checkServiceStatus(Permission permission) async {
    return ServiceStatus.enabled;
  }

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async {
    requests++;
    if (throwAlreadyOnRequest) {
      if (grantAfterRequestAttempt) {
        status = PermissionStatus.granted;
      }
      throw PlatformException(
        code: CameraPermission.alreadyRequestingCode,
        message: 'A request for permissions is already running',
      );
    }
    final gate = block;
    if (gate != null) await gate.future;
    status = PermissionStatus.granted;
    return {for (final permission in permissions) permission: status};
  }

  @override
  Future<bool> shouldShowRequestPermissionRationale(
    Permission permission,
  ) async {
    return false;
  }
}
