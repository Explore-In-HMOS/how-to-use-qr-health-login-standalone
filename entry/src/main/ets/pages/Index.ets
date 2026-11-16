import { image } from '@kit.ImageKit';
import { LoginUiState } from '../model/LoginUiState';
import { PreferencesTokenStore } from '../service/PreferencesTokenStore';
import { DeviceLoginViewModel } from '../viewmodel/DeviceLoginViewModel';

@Entry
@Component
struct Index {
  private viewModel: DeviceLoginViewModel = new DeviceLoginViewModel(new PreferencesTokenStore(getContext(this)));

  @State uiState: LoginUiState = 'IDLE';
  @State qr: image.PixelMap | null = null;
  @State errorMessage: string = '';

  @State steps: number | null = null;
  @State logs: string[] = [];
  @State refreshAvailable: boolean = false;
  @State tokenValidMinutes: number = 0;
  @State showActions: boolean = false;
  @State showCancel: boolean = false;
  @State busy: boolean = false;

  aboutToAppear(): void {
    this.viewModel.onChange = () => {
      this.uiState = this.viewModel.state;
      this.qr = this.viewModel.qrPixelMap;
      this.errorMessage = this.viewModel.errorMessage;

      this.steps = this.viewModel.steps;
      this.logs = this.viewModel.logs;
      this.refreshAvailable = this.viewModel.refreshTokenAvailable;
      this.tokenValidMinutes = this.viewModel.tokenValidMinutes;
      this.showActions = this.viewModel.canFetchSteps();
      this.showCancel = this.viewModel.canCancel();
      this.busy = this.viewModel.isBusy();
    };
    this.viewModel.launch();
  }

  onPageShow(): void {
    this.viewModel.resume();
  }

  onPageHide(): void {
    this.viewModel.pause();
  }

  aboutToDisappear(): void {
    this.viewModel.dispose();
  }

  private isLoggedIn(): boolean {
    return this.uiState === 'READY' ||
      this.uiState === 'FETCHING_STEPS' ||
      this.uiState === 'STEPS_READY' ||
      this.uiState === 'REFRESHING_TOKEN' ||
      this.uiState === 'TOKEN_REFRESHED';
  }

  build() {
    Scroll() {
      Column({ space: 6 }) {
        if (this.uiState === 'LOADING') {
          LoadingProgress().width(48).height(48)
          Text('Preparing...').fontSize(13).fontColor('#B0B0B0')

        } else if (this.uiState === 'WAITING' && this.qr) {
          Text('Scan with your phone').fontSize(14).fontColor('#FFFFFF')
          Image(this.qr)
            .width(140)
            .height(140)
            .borderRadius(8)
            .backgroundColor('#FFFFFF')
          Text('Approve permissions')
            .fontSize(11)
            .fontColor('#9E9E9E')
            .textAlign(TextAlign.Center)

        } else if (this.uiState === 'QR_STALE') {
          Text('Code expired').fontSize(14).fontColor('#FFFFFF')
          Button('Refresh')
            .fontSize(13)
            .onClick(() => this.viewModel.start())

        } else if (this.uiState === 'SUCCESS') {
          Text('✓').fontSize(40).fontColor('#4CAF50')
          Text('Signed in').fontSize(15).fontColor('#FFFFFF')

        } else if (this.isLoggedIn()) {
          Column({ space: 2 }) {
            if (this.uiState === 'TOKEN_REFRESHED') {
              Text('✓').fontSize(34).fontColor('#4CAF50')
              Text('Token renewed').fontSize(13).fontColor('#FFFFFF')
              Text(`valid ${this.tokenValidMinutes} min · no QR needed`)
                .fontSize(10)
                .fontColor('#4CAF50')
                .textAlign(TextAlign.Center)
            } else {
              if (this.steps !== null) {
                Text(`${this.steps}`).fontSize(32).fontColor('#4CAF50')
                Text('steps').fontSize(11).fontColor('#9E9E9E')
              } else {
                Text('Signed in').fontSize(14).fontColor('#FFFFFF')
              }
              if (this.tokenValidMinutes > 0) {
                Text(`access_token · ${this.tokenValidMinutes} min`)
                  .fontSize(10)
                  .fontColor('#9E9E9E')
              }
              if (this.refreshAvailable) {
                Text('refresh_token · 180 days')
                  .fontSize(10)
                  .fontColor('#4CAF50')
              }
              if (this.uiState === 'REFRESHING_TOKEN') {
                Text('Refreshing token...').fontSize(11).fontColor('#B0B0B0')
              } else if (this.uiState === 'FETCHING_STEPS') {
                Text('Fetching step data...').fontSize(11).fontColor('#B0B0B0')
              }
            }
          }
          .height(80)
          .justifyContent(FlexAlign.Center)

        } else if (this.uiState === 'FAILED') {
          Text(this.errorMessage)
            .fontSize(12)
            .fontColor('#FF6B6B')
            .textAlign(TextAlign.Center)
            .margin({ left: 12, right: 12 })
          Button('Try again')
            .fontSize(13)
            .onClick(() => this.viewModel.start())
        }

        if (this.showActions) {
          Button(this.steps === null ? 'Get my steps' : 'Refresh')
            .fontSize(12)
            .height(30)
            .enabled(!this.busy)
            .onClick(() => { this.viewModel.fetchStepsNow(); })

          Button('Refresh token')
            .fontSize(12)
            .height(30)
            .backgroundColor('#333333')
            .enabled(!this.busy)
            .onClick(() => { this.viewModel.refreshAccessToken(); })
        }

        if (this.showCancel) {
          Button('Sign out')
            .fontSize(11)
            .height(28)
            .backgroundColor('#5A2A2A')
            .onClick(() => { this.viewModel.cancelAuth(); })
        }

        if (this.isLoggedIn() && this.logs.length > 0) {
          Divider().color('#333333').margin({ top: 2, bottom: 2 })
          Column({ space: 2 }) {
            ForEach(this.logs.slice(0, 4), (line: string) => {
              Text(line)
                .fontSize(9)
                .fontColor('#777777')
                .textAlign(TextAlign.Start)
                .width('100%')
            }, (line: string, index?: number) => `${index}-${line}`)
          }
          .width('86%')
        }
      }
      .width('100%')
      .padding({ top: 10, bottom: 10 })
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    .scrollBar(BarState.Off)
    .align(Alignment.Center)
  }
}
