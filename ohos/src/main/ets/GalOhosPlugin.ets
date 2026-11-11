import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import util from '@ohos.util';
import { FlutterPlugin, FlutterPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import AbilityAware from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityAware';
import { AbilityPluginBinding } from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityPluginBinding';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import MethodChannel, { MethodCallHandler, MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';

class GalleryError extends Error {
  readonly galCode: string;

  constructor(code: string, message: string) {
    super(message);
    this.galCode = code;
  }
}

export default class GalOhosPlugin implements FlutterPlugin, AbilityAware, MethodCallHandler {
  private channel: MethodChannel | null = null;
  private context: common.UIAbilityContext | null = null;

  getUniqueClassName(): string {
    return 'GalOhosPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'gal');
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.context = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.context = binding.getAbility().context;
  }

  onDetachedFromAbility(): void {
    this.context = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'hasAccess':
      case 'requestAccess':
        // Public saves use a per-operation system dialog, so no persistent grant is needed.
        result.success(this.context !== null && call.argument('toAlbum') !== true);
        return;
      case 'putImage':
      case 'putImageBytes':
      case 'putVideo':
        this.save(call, result);
        return;
      case 'open':
        this.open(result);
        return;
      default:
        result.notImplemented();
    }
  }

  private async save(call: MethodCall, result: MethodResult): Promise<void> {
    let temporaryPath: string | undefined;
    let destinationUri: string | undefined;
    let completed = false;
    let helper: photoAccessHelper.PhotoAccessHelper | undefined;
    let sourceFile: fileIo.File | undefined;
    try {
      const context = this.context;
      if (context === null) {
        throw new GalleryError('UNEXPECTED', 'Gallery saving requires an attached foreground ability.');
      }
      const album = call.argument('album') as string | null | undefined;
      if (album !== null && album !== undefined) {
        throw new GalleryError('UNEXPECTED', 'Custom albums are not supported by HarmonyOS system-confirmed saves.');
      }
      const isVideo = call.method === 'putVideo';
      let sourcePath: string;
      let title: string;
      let extension: string;
      if (call.method === 'putImageBytes') {
        const bytes = call.argument('bytes') as Uint8Array;
        const data = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
        const source = image.createImageSource(data);
        if (source === undefined) {
          throw new GalleryError('NOT_SUPPORTED_FORMAT', 'The image bytes could not be decoded.');
        }
        try {
          const info = await source.getImageInfo();
          const mimeType = info.mimeType;
          const extensions: Record<string, string> = {
            'image/png': 'png',
            'image/jpeg': 'jpg',
            'image/gif': 'gif',
            'image/webp': 'webp',
            'image/heif': 'heif',
            'image/heic': 'heic',
            'image/bmp': 'bmp'
          };
          extension = extensions[mimeType];
          if (extension === undefined) {
            throw new GalleryError('NOT_SUPPORTED_FORMAT', 'Unsupported image format: ' + mimeType);
          }
        } catch (cause) {
          if (cause instanceof GalleryError) {
            throw cause;
          }
          throw new GalleryError('NOT_SUPPORTED_FORMAT', 'The image bytes could not be decoded.');
        } finally {
          await source.release();
        }
        sourcePath = context.cacheDir + '/gal-' + util.generateRandomUUID(false) + '.' + extension;
        temporaryPath = sourcePath;
        const file = fileIo.openSync(sourcePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY);
        try {
          const length = await fileIo.write(file.fd, data);
          if (length !== bytes.byteLength) {
            throw new GalleryError('UNEXPECTED', 'The temporary image could not be completely written.');
          }
        } finally {
          fileIo.closeSync(file);
        }
        title = call.argument('name') as string;
      } else {
        sourcePath = call.argument('path') as string;
        const fileName = sourcePath.substring(sourcePath.lastIndexOf('/') + 1);
        const separator = fileName.lastIndexOf('.');
        if (separator <= 0 || separator === fileName.length - 1) {
          throw new GalleryError('NOT_SUPPORTED_FORMAT', 'The file path must include a media extension.');
        }
        title = fileName.substring(0, separator);
        extension = fileName.substring(separator + 1).toLowerCase();
      }
      sourceFile = fileIo.openSync(sourcePath, fileIo.OpenMode.READ_ONLY);
      const sourceStat = fileIo.statSync(sourceFile.fd);
      if (!sourceStat.isFile() || sourceStat.size === 0) {
        throw new GalleryError('NOT_SUPPORTED_FORMAT', 'The media source must be a non-empty regular file.');
      }
      if (this.context !== context) {
        throw new GalleryError('UNEXPECTED', 'The ability detached before the save dialog could be opened.');
      }
      helper = photoAccessHelper.getPhotoAccessHelper(context);
      const sourceUri = sourcePath.startsWith('file://') ? sourcePath : fileUri.getUriFromPath(sourcePath);
      const targets = await helper.showAssetsCreationDialog([sourceUri], [{
        title: title,
        fileNameExtension: extension,
        photoType: isVideo ? photoAccessHelper.PhotoType.VIDEO : photoAccessHelper.PhotoType.IMAGE
      }]);
      if (targets.length === 0) {
        throw new GalleryError('ACCESS_DENIED', 'The user cancelled the gallery save.');
      }
      if (targets[0] === '-2004') {
        throw new GalleryError('NOT_SUPPORTED_FORMAT', 'The media type does not match the file extension.');
      }
      if (!targets[0].startsWith('file://')) {
        throw new GalleryError('UNEXPECTED', 'The system could not create the media asset: ' + targets[0]);
      }
      // After confirmation, complete the authorized write even if the ability detaches.
      destinationUri = targets[0];
      const destination = fileIo.openSync(destinationUri, fileIo.OpenMode.WRITE_ONLY);
      try {
        await fileIo.copyFile(sourceFile.fd, destination.fd);
        await fileIo.fsync(destination.fd);
      } finally {
        fileIo.closeSync(destination);
      }
      completed = true;
      result.success(null);
    } catch (cause) {
      if (cause instanceof GalleryError) {
        result.error(cause.galCode, cause.message, null);
      } else {
        const error = cause as BusinessError;
        let code = 'UNEXPECTED';
        if (error.code === 201 || error.code === 13900012) {
          code = 'ACCESS_DENIED';
        } else if (error.code === 13900025) {
          code = 'NOT_ENOUGH_SPACE';
        }
        result.error(code, error.message, null);
      }
    } finally {
      if (sourceFile !== undefined) {
        try {
          fileIo.closeSync(sourceFile);
        } catch (_) {
          // A close failure must not skip the remaining cleanup or replace the save result.
        }
      }
      if (!completed && destinationUri !== undefined) {
        try {
          // Only a fresh URI created for this call is eligible for rollback.
          fileIo.unlinkSync(destinationUri);
        } catch (_) {
          // The provider may restrict deletion; preserve the original save error.
        }
      }
      if (temporaryPath !== undefined) {
        try {
          fileIo.unlinkSync(temporaryPath);
        } catch (_) {
          // Cache cleanup does not change a completed save result.
        }
      }
      if (helper !== undefined) {
        try {
          await helper.release();
        } catch (_) {
          // Releasing the helper does not change the media write result.
        }
      }
    }
  }

  private async open(result: MethodResult): Promise<void> {
    try {
      const context = this.context;
      if (context === null) {
        throw new Error('Opening the gallery requires an attached foreground ability.');
      }
      await context.startAbility({
        action: 'ohos.want.action.viewData',
        type: 'image/*'
      });
      result.success(null);
    } catch (cause) {
      const error = cause as BusinessError;
      result.error('UNEXPECTED', 'The system could not open a gallery handler: ' + error.message, null);
    }
  }
}
