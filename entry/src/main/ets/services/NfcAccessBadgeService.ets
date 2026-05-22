import { tag } from '@kit.ConnectivityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { NfcDebugLogger } from './NfcDebugLogger';

const NDEF_READ_TIMEOUT_MS = 800;
const DEMO_BADGE_ID = 'HW-WATCH-042';
const DEMO_HOLDER_NAME = 'Alex Chen';
const ALLOWED_DOOR_ID = 'LAB-A';
const ALLOWED_ACCESS_LEVEL = 'staff';
const SNAPSHOT_NDEF_MESSAGE_KEY = 'NdefMsg';

export type AccessDecision = 'Ready' | 'Scanning' | 'Granted' | 'Denied' | 'Unsupported Tag' | 'Read Failed';

/**
 * Parsed access-badge payload carried by an NDEF text record.
 */
export interface BadgeProfile {
  badgeId: string;
  holderName: string;
  doorId: string;
  accessLevel: string;
}

/**
 * Full NFC scan result consumed by the UI.
 */
export interface BadgeScanStatus {
  decision: AccessDecision;
  profile?: BadgeProfile;
  isConnected: boolean;
  timeoutMs: number;
  maxTransmitSize: number;
  ndefRecordCount: number;
  tagTechSummary: string;
  tagUid: string;
  scanSource: string;
  errorMessage: string;
}

/**
 * JSON-safe projection of TagInfo used to inspect snapshot NDEF metadata.
 */
interface SerializedTagInfo extends tag.TagInfo {
  extrasData?: SerializedTagExtras[];
}

/**
 * Serialized extras block that may contain an already-read NDEF message.
 */
type SerializedTagExtras = Record<string, string | undefined>;

export class NfcAccessBadgeService {
  /**
   * Creates the default idle state shown before any scan is attempted.
   *
   * @returns Ready scan state with empty badge data.
   */
  createReadyStatus(): BadgeScanStatus {
    return {
      decision: 'Ready',
      isConnected: false,
      timeoutMs: 0,
      maxTransmitSize: 0,
      ndefRecordCount: 0,
      tagTechSummary: 'NDEF / NFC-A',
      tagUid: '',
      scanSource: 'Waiting',
      errorMessage: ''
    };
  }

  /**
   * Creates the transient state shown while a real tag is being processed.
   *
   * @returns Scanning state with default tag metadata.
   */
  createScanningStatus(): BadgeScanStatus {
    return {
      decision: 'Scanning',
      isConnected: false,
      timeoutMs: 0,
      maxTransmitSize: 0,
      ndefRecordCount: 0,
      tagTechSummary: 'NDEF / NFC-A',
      tagUid: '',
      scanSource: 'Reader mode',
      errorMessage: ''
    };
  }

  /**
   * Creates a failed scan state for reader-mode or framework errors.
   *
   * @param message Error message to show on the details page.
   * @returns Failed scan state.
   */
  createErrorStatus(message: string): BadgeScanStatus {
    return {
      decision: 'Read Failed',
      isConnected: false,
      timeoutMs: 0,
      maxTransmitSize: 0,
      ndefRecordCount: 0,
      tagTechSummary: 'NDEF / NFC-A',
      tagUid: '',
      scanSource: 'Reader mode',
      errorMessage: message
    };
  }

  /**
   * Runs a deterministic demo badge scan without touching NFC hardware.
   *
   * @returns Granted or denied demo result based on the sample badge profile.
   */
  scanDemoBadge(): BadgeScanStatus {
    NfcDebugLogger.info('Demo scan requested.');
    const profile = this.createDemoProfile();
    NfcDebugLogger.info(`Demo decision: ${this.isAllowed(profile) ? 'Access Granted' : 'Access Denied'}.`);
    return {
      decision: this.isAllowed(profile) ? 'Granted' : 'Denied',
      profile,
      isConnected: false,
      timeoutMs: 0,
      maxTransmitSize: 0,
      ndefRecordCount: 1,
      tagTechSummary: 'Demo NDEF',
      tagUid: 'Demo',
      scanSource: 'Demo',
      errorMessage: ''
    };
  }

  /**
   * Reads and evaluates a real NFC tag received from HarmonyOS reader mode.
   *
   * @param tagInfo Raw tag information delivered by the NFC framework.
   * @returns Complete badge scan status for the UI.
   */
  async scanTag(tagInfo: tag.TagInfo): Promise<BadgeScanStatus> {
    NfcDebugLogger.info('Real tag scan started.');
    let isConnected = false;
    let timeoutMs = 0;
    let maxTransmitSize = 0;
    let ndefRecordCount = 0;
    let tagTechSummary = this.describeTechnologies(tagInfo);
    const tagUid = this.formatUid(tagInfo.uid);
    let ndefTag: tag.NdefTag | undefined = undefined;

    try {
      NfcDebugLogger.info(`Detected technologies: ${tagTechSummary}.`);
      if (!this.hasTechnology(tagInfo, tag.NDEF)) {
        NfcDebugLogger.warn('Detected tag does not advertise NDEF technology.');
        const metadataSummary = this.readNfcASummary(tagInfo);
        return {
          decision: 'Unsupported Tag',
          isConnected,
          timeoutMs,
          maxTransmitSize,
          ndefRecordCount,
          tagTechSummary: metadataSummary,
          tagUid,
          scanSource: 'Reader mode',
          errorMessage: `Detected ${tagTechSummary}; expected NDEF text badge`
        };
      }

      const snapshotPayloads = this.readSnapshotNdefPayloads(tagInfo);
      if (snapshotPayloads.length > 0) {
        ndefRecordCount = snapshotPayloads.length;
        tagTechSummary = this.readNfcASummary(tagInfo);
        NfcDebugLogger.info(`NDEF snapshot records read: ${ndefRecordCount}.`);
        const profile = this.parseBadgeProfilePayloads(snapshotPayloads);
        if (profile === undefined) {
          NfcDebugLogger.warn('No supported badge payload found in NDEF snapshot.');
          return {
            decision: 'Unsupported Tag',
            isConnected,
            timeoutMs,
            maxTransmitSize,
            ndefRecordCount,
            tagTechSummary,
            tagUid,
            scanSource: 'TagInfo snapshot',
            errorMessage: 'Expected badge payload: badgeId|holder|door|access'
          };
        }

        const decision: AccessDecision = this.isAllowed(profile) ? 'Granted' : 'Denied';
        NfcDebugLogger.info(`Parsed badge payload: door=${profile.doorId}, access=${profile.accessLevel}.`);
        NfcDebugLogger.info(`Access decision: ${decision === 'Granted' ? 'Access Granted' : 'Access Denied'}.`);

        return {
          decision,
          profile,
          isConnected,
          timeoutMs,
          maxTransmitSize,
          ndefRecordCount,
          tagTechSummary,
          tagUid,
          scanSource: 'TagInfo snapshot',
          errorMessage: ''
        };
      }

      NfcDebugLogger.info('Creating NDEF tag object.');
      ndefTag = tag.getNdef(tagInfo);

      if (!ndefTag.isConnected()) {
        NfcDebugLogger.info('Tag is not connected. Connecting...');
        ndefTag.connect();
      }

      isConnected = ndefTag.isConnected();
      NfcDebugLogger.info(`Tag connected: ${isConnected}.`);
      ndefTag.setTimeout(NDEF_READ_TIMEOUT_MS);
      timeoutMs = ndefTag.getTimeout();
      maxTransmitSize = ndefTag.getMaxTransmitSize();
      NfcDebugLogger.info(`Session timeout=${timeoutMs} ms, maxTransmit=${maxTransmitSize} bytes.`);

      NfcDebugLogger.info('Reading NDEF message.');
      const ndefMessage = await ndefTag.readNdef();
      const records = ndefMessage.getNdefRecords();
      ndefRecordCount = records.length;
      NfcDebugLogger.info(`NDEF records read: ${ndefRecordCount}.`);
      tagTechSummary = this.readNfcASummary(tagInfo);

      const profile = this.parseBadgeProfile(records);
      if (profile === undefined) {
        NfcDebugLogger.warn('No supported badge payload found.');
        this.tryResetConnection(ndefTag);
        return {
          decision: 'Unsupported Tag',
          isConnected,
          timeoutMs,
          maxTransmitSize,
          ndefRecordCount,
          tagTechSummary,
          tagUid,
          scanSource: 'Live NDEF read',
          errorMessage: 'Expected badge payload: badgeId|holder|door|access'
        };
      }

      const decision: AccessDecision = this.isAllowed(profile) ? 'Granted' : 'Denied';
      NfcDebugLogger.info(`Parsed badge payload: door=${profile.doorId}, access=${profile.accessLevel}.`);
      NfcDebugLogger.info(`Access decision: ${decision === 'Granted' ? 'Access Granted' : 'Access Denied'}.`);

      this.tryResetConnection(ndefTag);

      return {
        decision,
        profile,
        isConnected,
        timeoutMs,
        maxTransmitSize,
        ndefRecordCount,
        tagTechSummary,
        tagUid,
        scanSource: 'Live NDEF read',
        errorMessage: ''
      };
    } catch (err) {
      this.tryResetConnection(ndefTag);
      const error = err as BusinessError;
      NfcDebugLogger.error(`Real tag scan failed: code=${error.code}, message=${error.message}`);
      return {
        decision: 'Read Failed',
        isConnected,
        timeoutMs,
        maxTransmitSize,
        ndefRecordCount,
        tagTechSummary,
        tagUid,
        scanSource: 'Reader mode',
        errorMessage: `code=${error.code}, message=${error.message}`
      };
    }
  }

  /**
   * Resets an open NDEF connection without letting cleanup errors override scan results.
   *
   * @param ndefTag Optional connected NDEF tag.
   */
  private tryResetConnection(ndefTag: tag.NdefTag | undefined): void {
    if (ndefTag === undefined) {
      return;
    }

    try {
      NfcDebugLogger.info('Resetting tag connection.');
      ndefTag.resetConnection();
      NfcDebugLogger.info('Tag connection reset.');
    } catch (_) {
      NfcDebugLogger.warn('Tag connection reset failed or was not needed.');
    }
  }

  /**
   * Reads NFC-A metadata and combines it with the technology summary.
   *
   * @param tagInfo Raw tag information.
   * @returns Display-friendly technology details.
   */
  private readNfcASummary(tagInfo: tag.TagInfo): string {
    try {
      NfcDebugLogger.info('Reading NFC-A metadata.');
      const nfcATag = tag.getNfcA(tagInfo);
      const sak = nfcATag.getSak();
      const atqa = nfcATag.getAtqa();
      return `${this.describeTechnologies(tagInfo)} sak=${sak}, atqa=${atqa.join(',')}`;
    } catch (_) {
      NfcDebugLogger.warn('NFC-A metadata unavailable.');
      return this.describeTechnologies(tagInfo);
    }
  }

  /**
   * Formats the raw UID bytes as a hyphen-separated uppercase hexadecimal string.
   *
   * @param uid Raw UID bytes from TagInfo.
   * @returns Formatted UID, or an empty string when the UID is unavailable.
   */
  private formatUid(uid: number[]): string {
    const parts: string[] = [];
    for (let index = 0; index < uid.length; index++) {
      const hex = uid[index].toString(16).toUpperCase();
      parts.push(hex.length === 1 ? `0${hex}` : hex);
    }
    return parts.join('-');
  }

  /**
   * Checks whether the tag advertises a specific NFC technology.
   *
   * @param tagInfo Raw tag information.
   * @param technology HarmonyOS NFC technology constant.
   * @returns True when the technology is present.
   */
  private hasTechnology(tagInfo: tag.TagInfo, technology: number): boolean {
    for (let index = 0; index < tagInfo.technology.length; index++) {
      if (tagInfo.technology[index] === technology) {
        return true;
      }
    }
    return false;
  }

  /**
   * Builds a display-friendly list of all detected NFC technologies.
   *
   * @param tagInfo Raw tag information.
   * @returns Slash-separated technology names.
   */
  private describeTechnologies(tagInfo: tag.TagInfo): string {
    const names: string[] = [];
    for (let index = 0; index < tagInfo.technology.length; index++) {
      names.push(this.technologyName(tagInfo.technology[index]));
    }
    return names.length > 0 ? names.join(' / ') : 'Unknown';
  }

  /**
   * Maps a HarmonyOS NFC technology constant to a readable label.
   *
   * @param technology HarmonyOS NFC technology constant.
   * @returns Display-friendly technology name.
   */
  private technologyName(technology: number): string {
    if (technology === tag.NFC_A) {
      return 'NFC-A';
    }
    if (technology === tag.NFC_B) {
      return 'NFC-B';
    }
    if (technology === tag.ISO_DEP) {
      return 'ISO-DEP';
    }
    if (technology === tag.NFC_F) {
      return 'NFC-F';
    }
    if (technology === tag.NFC_V) {
      return 'NFC-V';
    }
    if (technology === tag.NDEF) {
      return 'NDEF';
    }
    if (technology === tag.NDEF_FORMATABLE) {
      return 'NDEF formattable';
    }
    return `Tech ${technology}`;
  }

  /**
   * Creates the sample badge profile used by the demo scan path.
   *
   * @returns Static sample profile.
   */
  private createDemoProfile(): BadgeProfile {
    return {
      badgeId: DEMO_BADGE_ID,
      holderName: DEMO_HOLDER_NAME,
      doorId: ALLOWED_DOOR_ID,
      accessLevel: ALLOWED_ACCESS_LEVEL
    };
  }

  /**
   * Extracts raw payload bytes from live NDEF records and parses the badge profile.
   *
   * @param records NDEF records returned by the framework.
   * @returns Parsed badge profile when a supported record is found.
   */
  private parseBadgeProfile(records: tag.NdefRecord[]): BadgeProfile | undefined {
    const payloads: number[][] = [];
    for (let index = 0; index < records.length; index++) {
      payloads.push(records[index].payload);
    }
    return this.parseBadgeProfilePayloads(payloads);
  }

  /**
   * Attempts to parse each NDEF payload as a supported access-badge text record.
   *
   * @param payloads Raw NDEF payload byte arrays.
   * @returns First valid badge profile, if any.
   */
  private parseBadgeProfilePayloads(payloads: number[][]): BadgeProfile | undefined {
    for (let index = 0; index < payloads.length; index++) {
      const payloadText = this.decodePayload(payloads[index]);
      NfcDebugLogger.info(`Record ${index + 1} payload decoded, length=${payloadText.length}.`);
      const profile = this.parseProfileText(payloadText);
      if (profile !== undefined) {
        return profile;
      }
    }
    return undefined;
  }

  /**
   * Reads NDEF payloads that are already embedded in the TagInfo snapshot.
   *
   * @param tagInfo Raw tag information.
   * @returns Payload byte arrays parsed from snapshot metadata.
   */
  private readSnapshotNdefPayloads(tagInfo: tag.TagInfo): number[][] {
    const ndefHex = this.readSnapshotNdefHex(tagInfo);
    if (ndefHex.length === 0) {
      return [];
    }

    NfcDebugLogger.info('Reading NDEF message from TagInfo snapshot.');
    return this.parseNdefPayloads(this.hexToBytes(ndefHex));
  }

  /**
   * Extracts the snapshot NDEF message hex string from serialized TagInfo extras.
   *
   * @param tagInfo Raw tag information.
   * @returns Hex-encoded NDEF message or an empty string.
   */
  private readSnapshotNdefHex(tagInfo: tag.TagInfo): string {
    try {
      const serializedTagInfo = tagInfo as SerializedTagInfo;
      const extrasData = serializedTagInfo.extrasData;
      if (extrasData === undefined) {
        return '';
      }

      for (let index = 0; index < extrasData.length; index++) {
        const ndefMsg = extrasData[index][SNAPSHOT_NDEF_MESSAGE_KEY];
        if (ndefMsg !== undefined && ndefMsg.length > 0) {
          return ndefMsg;
        }
      }
    } catch (_) {
      NfcDebugLogger.warn('NDEF snapshot metadata unavailable.');
    }
    return '';
  }

  /**
   * Converts a hexadecimal string to bytes while skipping incomplete trailing nibbles.
   *
   * @param hex Hexadecimal string.
   * @returns Parsed bytes.
   */
  private hexToBytes(hex: string): number[] {
    const bytes: number[] = [];
    for (let index = 0; index + 1 < hex.length; index += 2) {
      const value = Number.parseInt(hex.substring(index, index + 2), 16);
      if (!Number.isNaN(value)) {
        bytes.push(value);
      }
    }
    return bytes;
  }

  /**
   * Parses a raw NDEF message into payload byte arrays.
   *
   * @param bytes Raw NDEF message bytes.
   * @returns Payloads from well-formed records encountered before message end.
   */
  private parseNdefPayloads(bytes: number[]): number[][] {
    const payloads: number[][] = [];
    let offset = 0;
    while (offset < bytes.length) {
      const header = bytes[offset];
      offset++;
      const isShortRecord = (header & 0x10) !== 0;
      const hasIdLength = (header & 0x08) !== 0;
      const isMessageEnd = (header & 0x40) !== 0;

      if (offset >= bytes.length) {
        return payloads;
      }

      const typeLength = bytes[offset];
      offset++;

      let payloadLength = 0;
      if (isShortRecord) {
        if (offset >= bytes.length) {
          return payloads;
        }
        payloadLength = bytes[offset];
        offset++;
      } else {
        if (offset + 3 >= bytes.length) {
          return payloads;
        }
        payloadLength = (bytes[offset] << 24) |
          (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3];
        offset += 4;
      }

      let idLength = 0;
      if (hasIdLength) {
        if (offset >= bytes.length) {
          return payloads;
        }
        idLength = bytes[offset];
        offset++;
      }

      const payloadStart = offset + typeLength + idLength;
      const payloadEnd = payloadStart + payloadLength;
      if (payloadEnd > bytes.length) {
        return payloads;
      }

      payloads.push(bytes.slice(payloadStart, payloadEnd));
      offset = payloadEnd;

      if (isMessageEnd) {
        return payloads;
      }
    }
    return payloads;
  }

  /**
   * Decodes an NDEF text payload, accounting for the optional language-code prefix.
   *
   * @param payload Raw NDEF payload bytes.
   * @returns Trimmed ASCII payload text.
   */
  private decodePayload(payload: number[]): string {
    if (payload.length === 0) {
      return '';
    }

    const textStart = this.getNdefTextStart(payload);
    return this.bytesToString(payload, textStart);
  }

  /**
   * Finds the first text byte in an NDEF text payload.
   *
   * @param payload Raw NDEF payload bytes.
   * @returns Offset after the language code, or zero for plain text fallback.
   */
  private getNdefTextStart(payload: number[]): number {
    const languageCodeLength = payload[0] & 0x3F;
    const textStart = languageCodeLength + 1;
    if (textStart >= payload.length || languageCodeLength === 0 || languageCodeLength > 8) {
      return 0;
    }

    for (let index = 1; index < textStart; index++) {
      const code = payload[index];
      const isLanguageChar = (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A) || code === 0x2D;
      if (!isLanguageChar) {
        return 0;
      }
    }
    return textStart;
  }

  /**
   * Converts printable ASCII bytes to a string from the given offset.
   *
   * @param payload Raw payload bytes.
   * @param start First byte offset to decode.
   * @returns Trimmed printable ASCII text.
   */
  private bytesToString(payload: number[], start: number): string {
    let value = '';
    for (let index = start; index < payload.length; index++) {
      const code = payload[index];
      if (code >= 0x20 && code <= 0x7E) {
        value += String.fromCharCode(code);
      }
    }
    return value.trim();
  }

  /**
   * Parses the access-badge text format: badgeId|holder|door|access.
   *
   * @param text Decoded payload text.
   * @returns Badge profile when all required fields are present.
   */
  private parseProfileText(text: string): BadgeProfile | undefined {
    const fields = text.split('|');
    if (fields.length < 4) {
      return undefined;
    }

    const badgeId = fields[0].trim();
    const holderName = fields[1].trim();
    const doorId = fields[2].trim();
    const accessLevel = fields[3].trim();

    if (badgeId.length === 0 || holderName.length === 0 || doorId.length === 0 || accessLevel.length === 0) {
      return undefined;
    }

    return {
      badgeId,
      holderName,
      doorId,
      accessLevel
    };
  }

  /**
   * Applies the demo access policy.
   *
   * @param profile Parsed badge profile.
   * @returns True when the badge may open the sample door.
   */
  private isAllowed(profile: BadgeProfile): boolean {
    return profile.doorId === ALLOWED_DOOR_ID && profile.accessLevel === ALLOWED_ACCESS_LEVEL;
  }
}
