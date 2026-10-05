import { AppError } from '../../../middleware/errors.js';
import type { LocationProvider, ProviderLocationResult } from '../../../providers/interfaces.js';

export interface HereLocationConfig { LOCATION_PROVIDER_API_KEY?: string; LOCATION_GEOCODE_BASE_URL?: string; LOCATION_SEARCH_BASE_URL?: string; LOCATION_PROVIDER_TIMEOUT_MS?: number; }

export class HereLocationProvider implements LocationProvider {
  private readonly apiKey: string; private readonly geocodeBase: URL; private readonly searchBase: URL; private readonly timeoutMs: number;
  constructor(config: HereLocationConfig) {
    if (!config.LOCATION_PROVIDER_API_KEY) throw new Error('Location provider API key is required');
    this.apiKey=config.LOCATION_PROVIDER_API_KEY; this.geocodeBase=new URL(config.LOCATION_GEOCODE_BASE_URL||'https://geocode.search.hereapi.com/v1'); this.searchBase=new URL(config.LOCATION_SEARCH_BASE_URL||'https://discover.search.hereapi.com/v1'); this.timeoutMs=config.LOCATION_PROVIDER_TIMEOUT_MS??10_000;
    if(this.geocodeBase.protocol!=='https:'||this.searchBase.protocol!=='https:') throw new Error('Location provider endpoints must use HTTPS');
  }
  getCapabilities(){return {available:true,reverseGeocode:true,search:true};}
  async reverseGeocode(input:{latitude:number;longitude:number}){const url=this.endpoint(this.geocodeBase,'revgeocode');url.searchParams.set('at',`${input.latitude},${input.longitude}`);return this.first(url);}
  async search(input:{query:string;limit:number}){const url=this.endpoint(this.searchBase,'discover');url.searchParams.set('q',input.query);url.searchParams.set('limit',String(Math.min(input.limit,10)));const payload=await this.request(url);const items=Array.isArray(payload.items)?payload.items:[];const results=items.map(item=>this.map(item)).filter(isUsable);if(items.length>0&&results.length===0)throw unavailable();return results;}
  private async first(url:URL){const payload=await this.request(url);const items=Array.isArray(payload.items)?payload.items:[];if(!items[0]||typeof items[0]!=='object')throw unavailable();const result=this.map(items[0]);if(!isUsable(result))throw unavailable();return result;}
  private endpoint(base:URL,path:string){const url=new URL(`${base.toString().replace(/\/$/,'')}/${path}`);url.searchParams.set('apiKey',this.apiKey);return url;}
  private async request(url:URL):Promise<{items?:unknown[]}>{const controller=new AbortController();const timer=setTimeout(()=>controller.abort(),this.timeoutMs);try{const response=await fetch(url,{method:'GET',redirect:'error',signal:controller.signal,headers:{accept:'application/json'}});if(!response.ok)throw unavailable();const payload=await response.json() as unknown;if(!payload||typeof payload!=='object')throw unavailable();return payload as {items?:unknown[]};}catch(error){if(error instanceof AppError)throw error;throw unavailable();}finally{clearTimeout(timer);}}
  private map(value:unknown):ProviderLocationResult{if(!value||typeof value!=='object')return{};const item=value as {address?:unknown;position?:unknown};const address=item.address&&typeof item.address==='object'?item.address as Record<string,unknown>:{};return {formattedAddress:stringValue(address.label),city:stringValue(address.city),region:stringValue(address.state),country:stringValue(address.countryName),countryCode:stringValue(address.countryCode),latitude:numberValue(item.position,'lat'),longitude:numberValue(item.position,'lng'),providerPlaceId:stringValue((value as Record<string,unknown>).id)};}
}
function stringValue(value:unknown){return typeof value==='string'&&value.trim()?value.trim():undefined;}
function numberValue(value:unknown,key:string){if(!value||typeof value!=='object')return undefined;const n=(value as Record<string,unknown>)[key];return typeof n==='number'&&Number.isFinite(n)?n:undefined;}
function isUsable(result:ProviderLocationResult){return Object.values(result).some(value=>value !== undefined && value !== null && value !== '');}
function unavailable():AppError{return new AppError('SERVICE_UNAVAILABLE','Location provider is unavailable');}
