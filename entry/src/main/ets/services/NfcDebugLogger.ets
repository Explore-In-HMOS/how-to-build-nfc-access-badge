import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const LOG_TAG = 'NfcAccessBadge';
const MAX_LOG_LINES = 32;

type LogListener = (logs: string[]) => void;

export class NfcDebugLogger {
  private static logs: string[] = [];
  private static listener?: LogListener;
  private static sequence: number = 0;

  /**
   * Registers a log listener and immediately replays the current in-memory log buffer.
   *
   * @param listener Optional UI listener that receives a copy of the log lines.
   */
  static setListener(listener?: LogListener): void {
    NfcDebugLogger.listener = listener;
    if (listener !== undefined) {
      listener([...NfcDebugLogger.logs]);
    }
  }

  /**
   * Records an informational message in both hilog and the visible debug log.
   *
   * @param message Message text to record.
   */
  static info(message: string): void {
    hilog.info(DOMAIN, LOG_TAG, '%{public}s', message);
    NfcDebugLogger.push(`I ${message}`);
  }

  /**
   * Records a warning message in both hilog and the visible debug log.
   *
   * @param message Message text to record.
   */
  static warn(message: string): void {
    hilog.warn(DOMAIN, LOG_TAG, '%{public}s', message);
    NfcDebugLogger.push(`W ${message}`);
  }

  /**
   * Records an error message in both hilog and the visible debug log.
   *
   * @param message Message text to record.
   */
  static error(message: string): void {
    hilog.error(DOMAIN, LOG_TAG, '%{public}s', message);
    NfcDebugLogger.push(`E ${message}`);
  }

  /**
   * Clears the in-memory log buffer and notifies the active listener.
   */
  static clear(): void {
    NfcDebugLogger.logs = [];
    NfcDebugLogger.sequence = 0;
    NfcDebugLogger.listener?.([...NfcDebugLogger.logs]);
  }

  /**
   * Adds one numbered line to the bounded log buffer.
   *
   * @param message Message already prefixed with its severity marker.
   */
  private static push(message: string): void {
    NfcDebugLogger.sequence++;
    const line = `${NfcDebugLogger.sequence}. ${message}`;
    NfcDebugLogger.logs.push(line);
    if (NfcDebugLogger.logs.length > MAX_LOG_LINES) {
      NfcDebugLogger.logs.shift();
    }
    NfcDebugLogger.listener?.([...NfcDebugLogger.logs]);
  }
}
