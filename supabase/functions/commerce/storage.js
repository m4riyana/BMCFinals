import {imageSize} from 'npm:image-size@2.0.2';
import {HttpError} from './lib/commerce.js';

export class ImageStorage {
  constructor(client) { this.client=client; this.bucket='ibasho-images'; }
  publicUrl(kind,file) {
    if (!['products','profiles'].includes(kind) || !/^[a-f0-9-]+\.(jpg|png|webp)$/.test(file)) return null;
    return this.client.storage.from(this.bucket).getPublicUrl(`${kind}/${file}`).data.publicUrl;
  }
  async upload(kind,bytes) {
    if (!['products','profiles'].includes(kind)) throw new HttpError(400,'Invalid image destination.');
    if (bytes.length>5*1024*1024) throw new HttpError(413,'Choose an image smaller than 5 MB.');
    let info;
    try { info=imageSize(bytes); } catch { throw new HttpError(400,'Upload a valid JPEG, PNG, or WebP image.'); }
    const types={jpg:'image/jpeg',png:'image/png',webp:'image/webp'};
    if (!types[info.type] || !info.width || !info.height || info.width*info.height>24000000) {
      throw new HttpError(400,'Choose a JPEG, PNG, or WebP image up to 24 megapixels.');
    }
    const file=`${crypto.randomUUID()}.${info.type}`;
    const {error}=await this.client.storage.from(this.bucket).upload(`${kind}/${file}`,bytes,{contentType:types[info.type],cacheControl:'31536000',upsert:false});
    if(error) throw new Error('Image storage upload failed');
    return `/uploads/${kind}/${file}`;
  }
  async remove(path) {
    if (typeof path!=='string' || !/^\/uploads\/profiles\/[a-f0-9-]+\.(jpg|png|webp)$/.test(path)) return;
    const {error}=await this.client.storage.from(this.bucket).remove([path.slice('/uploads/'.length)]);
    if(error) throw new Error('Image storage removal failed');
  }
}
