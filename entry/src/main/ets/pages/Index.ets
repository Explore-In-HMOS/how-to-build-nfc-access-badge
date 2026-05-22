import { tag } from '@kit.ConnectivityKit';
import {
  AccessDecision,
  BadgeScanStatus,
  NfcAccessBadgeService
} from '../services/NfcAccessBadgeService';
import { NfcDebugLogger } from '../services/NfcDebugLogger';
import { NfcTagDispatcher } from '../services/NfcTagDispatcher';

@Entry
@Component
struct Index {
  private service: NfcAccessBadgeService = new NfcAccessBadgeService();
  private scanRequestId: number = 0;

  @State visibleDecision: AccessDecision = 'Ready';
  @State visibleBadgeId: string = '';
  @State visibleHolderName: string = '';
  @State visibleDoorId: string = '';
  @State visibleAccessLevel: string = '';
  @State visibleIsConnected: boolean = false;
  @State visibleTimeoutMs: number = 0;
  @State visibleMaxTransmitSize: number = 0;
  @State visibleNdefRecordCount: number = 0;
  @State visibleTagTechSummary: string = 'NDEF / NFC-A';
  @State visibleTagUid: string = '';
  @State visibleScanSource: string = '';
  @State visibleErrorMessage: string = '';
  @State currentPage: number = 0;
  @State debugLogs: string[] = [];

  /**
   * Registers UI listeners for NFC scan results, NFC errors, and the in-app debug log.
   */
  aboutToAppear(): void {
    NfcDebugLogger.setListener((logs: string[]) => {
      this.debugLogs = logs;
    });
    NfcTagDispatcher.setTagInfoListener((tagInfo: tag.TagInfo) => {
      this.scanRealTag(tagInfo);
    });
    NfcTagDispatcher.setErrorListener((message: string) => {
      this.applyScanStatus(this.service.createErrorStatus(message));
      this.currentPage = 2;
    });
  }

  /**
   * Unregisters shared listeners so background callbacks do not update a destroyed page.
   */
  aboutToDisappear(): void {
    NfcDebugLogger.setListener(undefined);
    NfcTagDispatcher.setTagInfoListener(undefined);
    NfcTagDispatcher.setErrorListener(undefined);
  }

  /**
   * Runs the deterministic demo badge flow used by the manual scan button.
   */
  private runDemoScan(): void {
    this.scanRequestId++;
    this.applyScanStatus(this.service.scanDemoBadge());
    this.currentPage = 1;
  }

  /**
   * Resets the visible scan state and returns the swiper to the ready page.
   */
  private clearScan(): void {
    this.scanRequestId++;
    this.applyScanStatus(this.service.createReadyStatus());
    NfcDebugLogger.info('Screen cleared.');
    this.currentPage = 0;
  }

  /**
   * Handles a real NFC tag callback and ignores stale async scan results.
   *
   * @param tagInfo Tag information delivered by HarmonyOS reader mode.
   */
  private async scanRealTag(tagInfo: tag.TagInfo): Promise<void> {
    const requestId = ++this.scanRequestId;
    this.currentPage = 0;
    this.applyScanStatus(this.service.createScanningStatus());
    const status = await this.service.scanTag(tagInfo);
    if (requestId === this.scanRequestId) {
      this.applyScanStatus(status);
      this.currentPage = status.profile !== undefined ? 1 : 2;
    }
  }

  /**
   * Copies the canonical scan status into simple UI state fields for ArkUI binding.
   *
   * @param status Complete scan result produced by the NFC badge service.
   */
  private applyScanStatus(status: BadgeScanStatus): void {
    this.visibleDecision = status.decision;
    this.visibleBadgeId = status.profile?.badgeId ?? '';
    this.visibleHolderName = status.profile?.holderName ?? '';
    this.visibleDoorId = status.profile?.doorId ?? '';
    this.visibleAccessLevel = status.profile?.accessLevel ?? '';
    this.visibleIsConnected = status.isConnected;
    this.visibleTimeoutMs = status.timeoutMs;
    this.visibleMaxTransmitSize = status.maxTransmitSize;
    this.visibleNdefRecordCount = status.ndefRecordCount;
    this.visibleTagTechSummary = status.tagTechSummary;
    this.visibleTagUid = status.tagUid;
    this.visibleScanSource = status.scanSource;
    this.visibleErrorMessage = status.errorMessage;
    NfcDebugLogger.info(`UI status updated: ${status.decision}.`);
  }

  /**
   * Maps a scan decision to its localized display label.
   *
   * @param decision Current badge scan decision.
   * @returns A string resource for the decision.
   */
  private decisionText(decision: AccessDecision): ResourceStr {
    switch (decision) {
      case 'Scanning':
        return $r('app.string.status_scanning');
      case 'Granted':
        return $r('app.string.status_granted');
      case 'Denied':
        return $r('app.string.status_denied');
      case 'Unsupported Tag':
        return $r('app.string.status_unsupported');
      case 'Read Failed':
        return $r('app.string.status_failed');
      default:
        return $r('app.string.status_ready');
    }
  }

  /**
   * Chooses the foreground color used to display a scan decision.
   *
   * @param decision Current badge scan decision.
   * @returns A color resource for the decision text.
   */
  private decisionColor(decision: AccessDecision): ResourceColor {
    if (decision === 'Granted') {
      return $r('app.color.badge_success');
    }
    if (decision === 'Denied' || decision === 'Unsupported Tag' || decision === 'Read Failed') {
      return $r('app.color.badge_warning');
    }
    return $r('app.color.badge_primary');
  }

  /**
   * Chooses the soft background color used behind a scan decision.
   *
   * @param decision Current badge scan decision.
   * @returns A color resource for the decision surface.
   */
  private decisionBackground(decision: AccessDecision): ResourceColor {
    if (decision === 'Granted') {
      return $r('app.color.badge_success_soft');
    }
    if (decision === 'Denied' || decision === 'Unsupported Tag' || decision === 'Read Failed') {
      return $r('app.color.badge_warning_soft');
    }
    return $r('app.color.badge_primary_soft');
  }

  /**
   * Formats a boolean value as a localized yes/no label.
   *
   * @param value Boolean value shown in tag details.
   * @returns A localized yes/no resource.
   */
  private yesNo(value: boolean): ResourceStr {
    return value ? $r('app.string.value_yes') : $r('app.string.value_no');
  }

  /**
   * Returns the badge id or a localized empty-state placeholder.
   */
  private profileBadge(): ResourceStr {
    return this.visibleBadgeId.length > 0 ? this.visibleBadgeId : $r('app.string.value_no_badge');
  }

  /**
   * Returns the holder name or a localized empty-state placeholder.
   */
  private profileHolder(): ResourceStr {
    return this.visibleHolderName.length > 0 ? this.visibleHolderName : $r('app.string.value_no_badge');
  }

  /**
   * Returns the door id or a localized empty-state placeholder.
   */
  private profileDoor(): ResourceStr {
    return this.visibleDoorId.length > 0 ? this.visibleDoorId : $r('app.string.value_no_badge');
  }

  /**
   * Returns the access level or a localized empty-state placeholder.
   */
  private profileAccess(): ResourceStr {
    return this.visibleAccessLevel.length > 0 ? this.visibleAccessLevel : $r('app.string.value_no_badge');
  }

  /**
   * Returns the tag UID or a localized unavailable placeholder.
   */
  private tagUidText(): ResourceStr {
    return this.visibleTagUid.length > 0 ? this.visibleTagUid : $r('app.string.value_not_available');
  }

  /**
   * Returns the scan source or a localized unavailable placeholder.
   */
  private scanSourceText(): ResourceStr {
    return this.visibleScanSource.length > 0 ? this.visibleScanSource : $r('app.string.value_not_available');
  }

  /**
   * Builds the main round watch page with current scan status and primary actions.
   */
  @Builder
  private roundPage() {
    Column({ space: $r('app.float.round_page_gap') }) {
      Text($r('app.string.app_title'))
        .fontSize($r('app.float.title_text_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.badge_text_primary'))
        .textAlign(TextAlign.Center)
        .maxLines(1)

      this.statusDisk()

      Row({ space: $r('app.float.action_button_gap') }) {
        Button($r('app.string.scan_button'))
          .fontSize($r('app.float.button_text_size'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.badge_button_text_on_primary'))
          .backgroundColor($r('app.color.badge_primary'))
          .height($r('app.float.control_height'))
          .layoutWeight(1)
          .onClick(() => {
            this.runDemoScan();
          })

        Button($r('app.string.clear_button'))
          .fontSize($r('app.float.button_text_size'))
          .fontColor($r('app.color.badge_primary'))
          .backgroundColor($r('app.color.badge_primary_soft'))
          .height($r('app.float.control_height'))
          .layoutWeight(1)
          .onClick(() => {
            this.clearScan();
          })
      }
      .width('72%')
    }
    .width('100%')
    .height('100%')
    .padding({
      top: $r('app.float.round_page_top_padding'),
      bottom: $r('app.float.round_page_bottom_padding')
    })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  /**
   * Builds the badge result page shown after a supported badge payload is parsed.
   */
  @Builder
  private badgePage() {
    Column({ space: $r('app.float.result_page_gap') }) {
      Text($r('app.string.result_title'))
        .fontSize($r('app.float.title_text_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.badge_text_primary'))
        .textAlign(TextAlign.Center)
        .maxLines(1)

      Column({ space: $r('app.float.detail_panel_gap') }) {
        Row() {
          Text($r('app.string.label_door'))
            .fontSize($r('app.float.detail_text_size'))
            .fontColor($r('app.color.badge_text_secondary'))
            .maxLines(1)
            .layoutWeight(1)

          Text(this.profileDoor())
            .fontSize($r('app.float.detail_text_size'))
            .fontColor($r('app.color.badge_text_primary'))
            .fontWeight(FontWeight.Medium)
            .textAlign(TextAlign.End)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1.2)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)

        Row() {
          Text($r('app.string.label_badge'))
            .fontSize($r('app.float.detail_text_size'))
            .fontColor($r('app.color.badge_text_secondary'))
            .maxLines(1)
            .layoutWeight(1)

          Text(this.profileBadge())
            .fontSize($r('app.float.detail_text_size'))
            .fontColor($r('app.color.badge_text_primary'))
            .fontWeight(FontWeight.Medium)
            .textAlign(TextAlign.End)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1.2)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)

        Row() {
          Text($r('app.string.label_holder'))
            .fontSize($r('app.float.detail_text_size'))
            .fontColor($r('app.color.badge_text_secondary'))
            .maxLines(1)
            .layoutWeight(1)

          Text(this.profileHolder())
            .fontSize($r('app.float.detail_text_size'))
            .fontColor($r('app.color.badge_text_primary'))
            .fontWeight(FontWeight.Medium)
            .textAlign(TextAlign.End)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1.2)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)

        Row() {
          Text($r('app.string.label_access'))
            .fontSize($r('app.float.detail_text_size'))
            .fontColor($r('app.color.badge_text_secondary'))
            .maxLines(1)
            .layoutWeight(1)

          Text(this.profileAccess())
            .fontSize($r('app.float.detail_text_size'))
            .fontColor($r('app.color.badge_text_primary'))
            .fontWeight(FontWeight.Medium)
            .textAlign(TextAlign.End)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1.2)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .width('84%')
      .padding({
        left: $r('app.float.panel_padding'),
        right: $r('app.float.panel_padding'),
        top: $r('app.float.panel_padding'),
        bottom: $r('app.float.panel_padding')
      })
      .border({ width: 1, color: $r('app.color.badge_border') })
      .borderRadius($r('app.float.panel_radius'))
      .backgroundColor($r('app.color.badge_panel'))

      Text(this.decisionText(this.visibleDecision))
        .fontSize($r('app.float.body_text_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.decisionColor(this.visibleDecision))
        .textAlign(TextAlign.Center)
        .maxLines(1)
    }
    .width('100%')
    .height('100%')
    .padding({
      top: $r('app.float.page_padding'),
      bottom: $r('app.float.page_padding')
    })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  /**
   * Builds the technical tag-details page shown for scan diagnostics or errors.
   */
  @Builder
  private tagDetailsPage() {
    Column({ space: $r('app.float.detail_page_gap') }) {
      Text($r('app.string.details_title'))
        .fontSize($r('app.float.title_text_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.badge_text_primary'))
        .textAlign(TextAlign.Center)
        .maxLines(1)

      Scroll() {
        Column({ space: $r('app.float.detail_row_gap') }) {
          this.compactRow($r('app.string.label_connected'), this.yesNo(this.visibleIsConnected))
          this.compactRow($r('app.string.label_timeout'), $r('app.string.value_timeout_ms', this.visibleTimeoutMs))
          this.compactRow($r('app.string.label_max_transmit'), $r('app.string.value_bytes', this.visibleMaxTransmitSize))
          this.compactRow($r('app.string.label_records'), `${this.visibleNdefRecordCount}`)
          this.compactRow($r('app.string.label_tech'), this.visibleTagTechSummary)
          this.compactRow($r('app.string.label_uid'), this.tagUidText())
          this.compactRow($r('app.string.label_source'), this.scanSourceText())
        }
        .width('100%')
      }
      .width('84%')
      .height('58%')
      .padding({
        left: $r('app.float.panel_padding'),
        right: $r('app.float.panel_padding'),
        top: $r('app.float.panel_padding'),
        bottom: $r('app.float.panel_padding')
      })
      .border({ width: 1, color: $r('app.color.badge_border') })
      .borderRadius($r('app.float.panel_radius'))
      .backgroundColor($r('app.color.badge_panel'))
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)

      if (this.visibleErrorMessage.length > 0) {
        Text(this.visibleErrorMessage)
          .fontSize($r('app.float.detail_text_size'))
          .fontColor($r('app.color.badge_warning'))
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('76%')
      }
    }
    .width('100%')
    .height('100%')
    .padding({
      top: $r('app.float.page_padding'),
      bottom: $r('app.float.page_padding')
    })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  /**
   * Builds the scrollable debug log page.
   */
  @Builder
  private logsPage() {
    Column({ space: $r('app.float.logs_page_gap') }) {
      Text($r('app.string.logs_title'))
        .fontSize($r('app.float.title_text_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.badge_text_primary'))
        .textAlign(TextAlign.Center)
        .maxLines(1)

      Scroll() {
        Column({ space: $r('app.float.logs_row_gap') }) {
          if (this.debugLogs.length === 0) {
            Text($r('app.string.logs_empty'))
              .fontSize($r('app.float.detail_text_size'))
              .fontColor($r('app.color.badge_text_secondary'))
              .textAlign(TextAlign.Center)
              .width('100%')
          } else {
            ForEach(this.debugLogs, (line: string) => {
              Text(line)
                .fontSize($r('app.float.detail_text_size'))
                .fontColor($r('app.color.badge_text_primary'))
                .textAlign(TextAlign.Start)
                .maxLines(3)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }, (line: string) => line)
          }
        }
        .width('100%')
      }
      .width('86%')
      .height('58%')
      .padding({
        left: $r('app.float.log_panel_horizontal_padding'),
        right: $r('app.float.log_panel_horizontal_padding'),
        top: $r('app.float.log_panel_vertical_padding'),
        bottom: $r('app.float.log_panel_vertical_padding')
      })
      .border({ width: 1, color: $r('app.color.badge_border') })
      .borderRadius($r('app.float.panel_radius'))
      .backgroundColor($r('app.color.badge_panel'))
      .scrollable(ScrollDirection.Vertical)
      .scrollBar(BarState.Auto)

      Button($r('app.string.clear_logs_button'))
        .fontSize($r('app.float.button_text_size'))
        .fontColor($r('app.color.badge_primary'))
        .backgroundColor($r('app.color.badge_primary_soft'))
        .height($r('app.float.control_height'))
        .width('54%')
        .onClick(() => {
          NfcDebugLogger.clear();
        })
    }
    .width('100%')
    .height('100%')
    .padding({
      top: $r('app.float.page_padding'),
      bottom: $r('app.float.page_padding')
    })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  /**
   * Builds a compact label/value row shared by small detail panels.
   *
   * @param label Localized row label.
   * @param value Row value or fallback placeholder.
   */
  @Builder
  private compactRow(label: ResourceStr, value: ResourceStr) {
    Row() {
      Text(label)
        .fontSize($r('app.float.detail_text_size'))
        .fontColor($r('app.color.badge_text_secondary'))
        .maxLines(1)
        .layoutWeight(1)

      Text(value)
        .fontSize($r('app.float.detail_text_size'))
        .fontColor($r('app.color.badge_text_primary'))
        .fontWeight(FontWeight.Medium)
        .textAlign(TextAlign.End)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1.2)
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
  }

  /**
   * Builds the circular status surface for the ready page.
   */
  @Builder
  private statusDisk() {
    Column({ space: $r('app.float.status_disk_gap') }) {
      Text(this.decisionText(this.visibleDecision))
        .fontSize($r('app.float.status_text_size'))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.decisionColor(this.visibleDecision))
        .textAlign(TextAlign.Center)
        .maxLines(2)

      Text($r('app.string.instruction_ready'))
        .fontSize($r('app.float.body_text_size'))
        .fontColor($r('app.color.badge_text_secondary'))
        .textAlign(TextAlign.Center)
        .maxLines(2)

      Text($r('app.string.scan_hint'))
        .fontSize($r('app.float.detail_text_size'))
        .fontColor($r('app.color.badge_text_secondary'))
        .textAlign(TextAlign.Center)
        .maxLines(2)
    }
    .width($r('app.float.status_disk_size'))
    .height($r('app.float.status_disk_size'))
    .padding($r('app.float.status_disk_padding'))
    .borderRadius($r('app.float.status_disk_radius'))
    .backgroundColor(this.decisionBackground(this.visibleDecision))
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * Builds the root swiper that hosts all watch pages.
   */
  build() {
    Swiper() {
      this.roundPage()
      this.badgePage()
      this.tagDetailsPage()
      this.logsPage()
    }
    .index(this.currentPage)
    .indicator(true)
    .loop(false)
    .duration(250)
    .onChange((index: number) => {
      this.currentPage = index;
    })
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.badge_background'))
  }
}
