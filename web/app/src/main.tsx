import { isIOSApp } from './native/ios';

// iOS renders SwiftUI. WebKit runs only the shared catalogue and stream resolver.
if (isIOSApp()) void import('./native/service');
else void import('./browser');
