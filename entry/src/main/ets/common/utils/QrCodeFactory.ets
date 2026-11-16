import { image } from '@kit.ImageKit';
import { generateBarcode, scanCore } from '@kit.ScanKit';

export class QrCodeFactory {
  static async create(content: string): Promise<image.PixelMap> {
    return generateBarcode.createBarcode(content, {
      scanType: scanCore.ScanType.QR_CODE,
      height: 280,
      width: 280,
      margin: 1
    });
  }
}
