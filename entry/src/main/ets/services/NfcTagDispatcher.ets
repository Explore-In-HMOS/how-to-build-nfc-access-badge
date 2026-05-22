import { tag } from '@kit.ConnectivityKit';
import { NfcDebugLogger } from './NfcDebugLogger';

type TagInfoListener = (tagInfo: tag.TagInfo) => void;
type ErrorListener = (message: string) => void;

export class NfcTagDispatcher {
  private static tagInfoListener?: TagInfoListener;
  private static errorListener?: ErrorListener;
  private static pendingTagInfo?: tag.TagInfo;
  private static pendingError: string = '';

  /**
   * Registers the active UI tag listener and flushes one pending tag callback if present.
   *
   * @param listener Optional listener owned by the current page instance.
   */
  static setTagInfoListener(listener?: TagInfoListener): void {
    NfcTagDispatcher.tagInfoListener = listener;
    if (listener !== undefined && NfcTagDispatcher.pendingTagInfo !== undefined) {
      NfcDebugLogger.info('Delivering pending tag info to UI.');
      const tagInfo = NfcTagDispatcher.pendingTagInfo;
      NfcTagDispatcher.pendingTagInfo = undefined;
      listener(tagInfo);
    }
  }

  /**
   * Registers the active UI error listener and flushes one pending NFC error if present.
   *
   * @param listener Optional listener owned by the current page instance.
   */
  static setErrorListener(listener?: ErrorListener): void {
    NfcTagDispatcher.errorListener = listener;
    if (listener !== undefined && NfcTagDispatcher.pendingError.length > 0) {
      NfcDebugLogger.info('Delivering pending NFC error to UI.');
      const message = NfcTagDispatcher.pendingError;
      NfcTagDispatcher.pendingError = '';
      listener(message);
    }
  }

  /**
   * Delivers tag information to the UI or stores it until the page listener is ready.
   *
   * @param tagInfo Raw HarmonyOS tag information from reader mode.
   */
  static dispatchTagInfo(tagInfo: tag.TagInfo): void {
    if (NfcTagDispatcher.tagInfoListener === undefined) {
      NfcDebugLogger.warn('Tag callback arrived before UI listener was ready.');
      NfcTagDispatcher.pendingTagInfo = tagInfo;
      return;
    }
    NfcDebugLogger.info('Tag callback delivered to UI.');
    NfcTagDispatcher.tagInfoListener(tagInfo);
  }

  /**
   * Delivers an NFC error to the UI or stores it until the page listener is ready.
   *
   * @param message Error message suitable for the debug/details screens.
   */
  static dispatchError(message: string): void {
    if (NfcTagDispatcher.errorListener === undefined) {
      NfcDebugLogger.warn(`NFC error arrived before UI listener: ${message}`);
      NfcTagDispatcher.pendingError = message;
      return;
    }
    NfcDebugLogger.error(message);
    NfcTagDispatcher.errorListener(message);
  }
}
