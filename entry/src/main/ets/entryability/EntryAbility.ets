import { AbilityConstant, bundleManager, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { tag } from '@kit.ConnectivityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { NfcDebugLogger } from '../services/NfcDebugLogger';
import { NfcTagDispatcher } from '../services/NfcTagDispatcher';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  private elementName?: bundleManager.ElementName;
  private isNfcDispatchRegistered: boolean = false;

  /**
   * Bridges HarmonyOS reader-mode callbacks into the page-level tag dispatcher.
   */
  private readerModeCallback = (err: BusinessError, tagInfo: tag.TagInfo): void => {
    NfcDebugLogger.info('Reader mode NFC callback fired.');
    if (err) {
      NfcDebugLogger.error(`Reader mode callback error: code=${err.code}, message=${err.message}`);
      NfcTagDispatcher.dispatchError(err.message);
      return;
    }
    NfcDebugLogger.info('TagInfo received by reader mode.');
    NfcTagDispatcher.dispatchTagInfo(tagInfo);
  };

  /**
   * Initializes app color mode and caches the ability identity required by NFC reader mode.
   *
   * @param want Launch intent used to derive the ability element name.
   * @param launchParam Launch metadata supplied by the framework.
   */
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    NfcDebugLogger.info('Ability created.');
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }

    this.elementName = {
      bundleName: want.bundleName ?? this.context.abilityInfo.bundleName,
      abilityName: want.abilityName ?? this.context.abilityInfo.name,
      moduleName: want.moduleName ?? this.context.abilityInfo.moduleName
    };
    NfcDebugLogger.info(`Element prepared: ${this.elementName.bundleName}/${this.elementName.abilityName}`);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  /**
   * Handles final ability teardown.
   */
  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  /**
   * Loads the main ArkUI page into the window stage.
   *
   * @param windowStage Window stage created by the framework.
   */
  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  /**
   * Releases foreground NFC registration when the window stage is destroyed.
   */
  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    this.unregisterNfcForegroundDispatch();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  /**
   * Registers NFC reader mode while the app is visible to the user.
   */
  onForeground(): void {
    // Ability has brought to foreground
    this.registerNfcForegroundDispatch();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  /**
   * Unregisters NFC reader mode when the app leaves the foreground.
   */
  onBackground(): void {
    // Ability has back to background
    this.unregisterNfcForegroundDispatch();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }

  /**
   * Enables NFC foreground dispatch once per foreground session.
   */
  private registerNfcForegroundDispatch(): void {
    if (this.elementName === undefined || this.isNfcDispatchRegistered) {
      if (this.isNfcDispatchRegistered) {
        NfcDebugLogger.info('Foreground dispatch already registered.');
      }
      return;
    }

    NfcDebugLogger.info('Checking NFC tag SysCap.');
    if (!canIUse('SystemCapability.Communication.NFC.Tag')) {
      NfcTagDispatcher.dispatchError('NFC tag capability is unavailable on this device.');
      return;
    }

    try {
      const discTech: number[] = [tag.NFC_A, tag.NFC_B, tag.NFC_F, tag.NFC_V];
      NfcDebugLogger.info('Enabling NFC reader mode.');
      tag.on('readerMode', this.elementName, discTech, this.readerModeCallback);
      this.isNfcDispatchRegistered = true;
      NfcDebugLogger.info('NFC reader mode enabled.');
    } catch (err) {
      const error = err as BusinessError;
      NfcDebugLogger.error(`readerMode enable failed: code=${error.code}, message=${error.message}`);
      NfcTagDispatcher.dispatchError(error.message);
      hilog.error(DOMAIN, 'testTag', 'readerMode enable failed. Cause: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * Disables NFC foreground dispatch and clears the registration flag.
   */
  private unregisterNfcForegroundDispatch(): void {
    if (this.elementName === undefined || !this.isNfcDispatchRegistered) {
      return;
    }

    try {
      NfcDebugLogger.info('Disabling NFC reader mode.');
      tag.off('readerMode', this.elementName, this.readerModeCallback);
      this.isNfcDispatchRegistered = false;
      NfcDebugLogger.info('NFC reader mode disabled.');
    } catch (err) {
      this.isNfcDispatchRegistered = false;
      const error = err as BusinessError;
      NfcDebugLogger.error(`readerMode disable failed: code=${error.code}, message=${error.message}`);
      hilog.error(DOMAIN, 'testTag', 'readerMode disable failed. Cause: %{public}s', JSON.stringify(err));
    }
  }
}
