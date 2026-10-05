import { createApp, type AppOptions } from './app.js';
import { loadConfig } from './config/env.js';
import { createLogger } from './config/logger.js';
import { createDbPool } from './database/client.js';
import { FirebaseAuthProvider } from './providers/firebase-auth.js';
import { AuthService } from './modules/auth/service.js';
import { AccountDeletionService } from './modules/auth/account-deletion.js';
import { createAuthRouter, createFirebaseAuthenticationMiddleware } from './modules/auth/routes.js';
import { ProfileService } from './modules/profiles/service.js';
import { createProfileRouter } from './modules/profiles/routes.js';
import { SocialService } from './modules/social/service.js';
import { createSocialRouter } from './modules/social/routes.js';
import { PostService } from './modules/posts/service.js';
import { createHomeRouter, createPostRouter } from './modules/posts/routes.js';
import { EngagementService } from './modules/engagement/service.js';
import { createEngagementRouter } from './modules/engagement/routes.js';
import { MarketplaceService } from './modules/marketplace/service.js';
import { createCategoryRouter, createMarketplaceRouter } from './modules/marketplace/routes.js';
import { DiscoverService } from './modules/discover/service.js';
import { createDiscoverRouter } from './modules/discover/routes.js';
import { CartService } from './modules/cart/service.js';
import { createCartRouter } from './modules/cart/routes.js';
import { OrderService } from './modules/orders/service.js';
import { createOrderRouter } from './modules/orders/routes.js';
import { ChatService } from './modules/chat/service.js';
import { ChatRepository } from './modules/chat/repository.js';
import { createChatRouter } from './modules/chat/routes.js';
import { SocialRepository } from './modules/social/repository.js';
import { TranslationRepository } from './modules/translation/repository.js';
import { TranslationService } from './modules/translation/service.js';
import { createTranslationRouter } from './modules/translation/routes.js';
import { UnavailableTranslationProvider } from './modules/translation/providers/unavailable.js';
import { GoogleCloudTranslationProvider } from './modules/translation/providers/google-cloud.js';
import { DeepLTranslationProvider } from './modules/translation/providers/deepl.js';
import { LocationRepository } from './modules/location/repository.js';
import { LocationService } from './modules/location/service.js';
import { createLocationRouter } from './modules/location/routes.js';
import { UnavailableLocationProvider } from './modules/location/providers/unavailable.js';
import { HereLocationProvider } from './modules/location/providers/here.js';
import { WalletRepository } from './modules/wallet/repository.js';
import { WalletService } from './modules/wallet/service.js';
import { createWalletRouter } from './modules/wallet/routes.js';
import { LedgerRepository } from './modules/ledger/repository.js';
import { LedgerService } from './modules/ledger/service.js';
import { QrRepository } from './modules/qr/repository.js';
import { QrService } from './modules/qr/service.js';
import { createQrRouter } from './modules/qr/routes.js';
import { BankService } from './modules/bank/service.js';
import { createBankRouter } from './modules/bank/routes.js';
import { PaystackBankProvider } from './modules/bank/providers/paystack.js';
import { UnavailableBankProvider } from './modules/bank/providers/unavailable.js';
import { BankTransferService } from './modules/bank/transfer-service.js';
import { createBankTransferRouter } from './modules/bank/transfer-routes.js';
import { VirtualAccountService } from './modules/bank/virtual-account-service.js';
import { createVirtualAccountRouter } from './modules/bank/virtual-account-routes.js';
import { PaymentRepository } from './modules/payments/repository.js';
import { PaymentService } from './modules/payments/service.js';
import { createPaymentRouter } from './modules/payments/routes.js';
import { UnavailablePaymentProvider } from './modules/payments/providers/unavailable.js';
import { PaystackPaymentProvider } from './modules/payments/providers/paystack.js';
import { NotificationService } from './modules/notifications/service.js';
import { FirebaseNotificationProvider } from './modules/notifications/providers/firebase.js';
import { createNotificationRouter } from './modules/notifications/routes.js';
import { DeepLinkService } from './modules/deep-links/service.js';
import { createDeepLinkRouter } from './modules/deep-links/routes.js';
import { AssistRepository } from './modules/assist/repository.js';
import { AssistService } from './modules/assist/service.js';
import { AssistToolRegistry } from './modules/assist/tools/registry.js';
import { createAssistRouter } from './modules/assist/routes.js';
import { OpenAICompatibleProvider } from './modules/assist/providers/openai-compatible.js';
import { UnavailableAIProvider } from './modules/assist/providers/unavailable.js';
import { RealtimeService } from './modules/realtime/service.js';
import { attachRealtimeGateway, type RealtimeGateway } from './modules/realtime/connection.js';
import { closeDbPool } from './database/client.js';
import { SettingsRepository } from './modules/settings/repository.js';
import { SettingsService } from './modules/settings/service.js';
import { createSettingsRouter } from './modules/settings/routes.js';
import { createBlockRouter } from './modules/blocks/routes.js';
import { safeErrorSummary } from './config/redaction.js';
import { ResendEmailProvider, UnavailableEmailProvider } from './providers/resend-email.js';
import { EmailVerificationService } from './modules/auth/email-verification.js';
import { createEmailVerificationRouter } from './modules/auth/email-verification-routes.js';
import { SupabaseStorageProvider } from './providers/supabase-storage.js';
import { MediaService } from './modules/media/service.js';
import { createMediaRouter } from './modules/media/routes.js';

const config = loadConfig();
const logger = createLogger(config);
let authOptions: AppOptions = {};
const pool = config.DATABASE_URL ? createDbPool(config) : undefined;
const storageProvider = config.SUPABASE_URL && config.SUPABASE_SERVICE_ROLE_KEY ? new SupabaseStorageProvider(config) : undefined;
let realtimeService: RealtimeService | undefined;
let firebaseProvider: FirebaseAuthProvider | undefined;
let authService: AuthService | undefined;

if (pool) {
  if (config.FIREBASE_PROJECT_ID && config.FIREBASE_CLIENT_EMAIL && config.FIREBASE_PRIVATE_KEY) {
    firebaseProvider = new FirebaseAuthProvider(config);
  }

  const emailProvider = config.RESEND_API_KEY && config.RESEND_FROM_EMAIL
    ? new ResendEmailProvider(config)
    : new UnavailableEmailProvider();

  if (firebaseProvider) {
    authOptions.emailVerificationRouter = createEmailVerificationRouter(
      new EmailVerificationService(pool, emailProvider, config),
      firebaseProvider
    );
  }

  authOptions.settingsRouter = createSettingsRouter(new SettingsService(new SettingsRepository(pool)));

  if (storageProvider) {
    authOptions.mediaRouter = createMediaRouter(new MediaService(storageProvider));
  }

  const chatRepository = new ChatRepository(pool);
  const socialRepository = new SocialRepository(pool);
  realtimeService = new RealtimeService(pool, chatRepository, socialRepository);
  const pushProvider = firebaseProvider ? new FirebaseNotificationProvider(pool, config) : undefined;
  const notificationService = new NotificationService(pool, undefined, realtimeService, pushProvider);
  const profileService = new ProfileService(pool, undefined, storageProvider);
  authOptions.profileRouter = createProfileRouter(profileService);
  const socialService = new SocialService(pool, socialRepository, notificationService);
  authOptions.socialRouter = createSocialRouter(socialService);
  authOptions.blockRouter = createBlockRouter(socialService);
  const postService = new PostService(pool, undefined, storageProvider);
  authOptions.postRouter = createPostRouter(postService);
  authOptions.homeRouter = createHomeRouter(postService);
  authOptions.engagementRouter = createEngagementRouter(new EngagementService(pool, undefined, notificationService));
  const marketplaceService = new MarketplaceService(pool, undefined, storageProvider);
  authOptions.marketplaceRouter = createMarketplaceRouter(marketplaceService);
  authOptions.marketplaceCategoryRouter = createCategoryRouter(marketplaceService);
  authOptions.discoverRouter = createDiscoverRouter(new DiscoverService(marketplaceService, socialService));
  authOptions.cartRouter = createCartRouter(new CartService(pool));
  const orderService = new OrderService(pool);
  authOptions.orderRouter = createOrderRouter(orderService);
  const chatService = new ChatService(pool, chatRepository, socialRepository, realtimeService, notificationService);
  authOptions.chatRouter = createChatRouter(chatService);
  const translationProvider = config.TRANSLATION_PROVIDER_API_KEY
    ? config.TRANSLATION_PROVIDER === 'google'
      ? new GoogleCloudTranslationProvider(config)
      : new DeepLTranslationProvider(config)
    : new UnavailableTranslationProvider();
  const translationService = new TranslationService(translationProvider, new TranslationRepository(pool));
  authOptions.translationRouter = createTranslationRouter(translationService);
  const locationProvider = config.LOCATION_PROVIDER_API_KEY
    ? new HereLocationProvider(config)
    : new UnavailableLocationProvider();
  authOptions.locationRouter = createLocationRouter(new LocationService(locationProvider, new LocationRepository()));
  const walletRepository = new WalletRepository(pool);
  const walletService = new WalletService(pool, walletRepository, new LedgerService(new LedgerRepository()));
  authOptions.walletRouter = createWalletRouter(walletService);
  authOptions.qrRouter = createQrRouter(new QrService(pool, new QrRepository(pool)), walletService);
  const bankProvider = config.PAYSTACK_ENABLED && config.PAYSTACK_SECRET_KEY ? new PaystackBankProvider(config) : new UnavailableBankProvider();
  const bankLedger = new LedgerService(new LedgerRepository());
  const virtualAccountService = new VirtualAccountService(pool, bankProvider, bankLedger);
  authOptions.bankRouter = createBankRouter(new BankService(bankProvider));
  authOptions.bankTransferRouter = createBankTransferRouter(new BankTransferService(pool, bankProvider, bankLedger), virtualAccountService);
  authOptions.virtualAccountRouter = createVirtualAccountRouter(virtualAccountService);
  const paymentProvider = config.PAYSTACK_ENABLED && config.PAYSTACK_SECRET_KEY
    ? new PaystackPaymentProvider(config)
    : new UnavailablePaymentProvider();
  authOptions.paymentRouter = createPaymentRouter(new PaymentService(pool, paymentProvider, new PaymentRepository(pool)), virtualAccountService);
  authOptions.notificationRouter = createNotificationRouter(notificationService);
  authOptions.deepLinkRouter = createDeepLinkRouter(new DeepLinkService({
    profiles: profileService,
    posts: postService,
    marketplace: marketplaceService,
    orders: orderService,
    notifications: notificationService,
    chat: chatService
  }, pool, socialRepository));
  const aiProvider = config.AI_PROVIDER_BASE_URL && config.AI_PROVIDER_API_KEY && config.AI_PROVIDER_MODEL
    ? new OpenAICompatibleProvider(config)
    : new UnavailableAIProvider();
  authOptions.assistRouter = createAssistRouter(new AssistService(
    pool,
    new AssistRepository(pool),
    aiProvider,
    new AssistToolRegistry(marketplaceService, translationService)
  ));
}

if (pool && firebaseProvider) {
  authService = new AuthService(pool, config, realtimeService);
  authOptions = {
    ...authOptions,
    authMiddleware: createFirebaseAuthenticationMiddleware(firebaseProvider, authService),
    authRouter: createAuthRouter(authService, new AccountDeletionService(pool, firebaseProvider, realtimeService))
  };
} else {
  logger.warn('Firebase authentication is unavailable until DATABASE_URL and Firebase Admin settings are configured');
}

const app = createApp(config, logger, {
  ...authOptions,
  readinessCheck: pool ? async () => {
    await pool.query('SELECT 1');
    return true;
  } : undefined
});
const server = app.listen(config.PORT, () => {
  logger.info({ port: config.PORT }, 'Eazy backend listening');
});
let realtimeGateway: RealtimeGateway | undefined;
if (pool && realtimeService && firebaseProvider && authService) {
  realtimeGateway = attachRealtimeGateway(server, config, firebaseProvider, authService, realtimeService, logger);
}

let shuttingDown = false;
async function shutdown(signal: string) {
  if (shuttingDown) return;
  shuttingDown = true;
  logger.info({ signal }, 'shutting down');
  try {
    if (realtimeGateway) await realtimeGateway.close();
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
    if (pool) await closeDbPool(pool);
    process.exit(0);
  } catch (error) {
    logger.error({ event: 'shutdown.failed', error: safeErrorSummary(error) }, 'shutdown failed');
    process.exit(1);
  }
}
process.on('SIGTERM', () => { void shutdown('SIGTERM'); });
process.on('SIGINT', () => { void shutdown('SIGINT'); });
process.on('uncaughtException', error => {
  logger.fatal({ event: 'process.uncaught_exception', error: safeErrorSummary(error) }, 'uncaught exception');
  void shutdown('uncaughtException');
});
process.on('unhandledRejection', reason => {
  logger.error({ event: 'process.unhandled_rejection', error: safeErrorSummary(reason) }, 'unhandled rejection');
  void shutdown('unhandledRejection');
});
