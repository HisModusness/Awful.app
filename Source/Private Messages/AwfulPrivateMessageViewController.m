//  AwfulPrivateMessageViewController.m
//
//  Copyright 2012 Awful Contributors. CC BY-NC-SA 3.0 US https://github.com/Awful/Awful.app

#import "AwfulPrivateMessageViewController.h"
#import "AwfulActionSheet.h"
#import "AwfulActionViewController.h"
#import "AwfulAlertView.h"
#import "AwfulAppDelegate.h"
#import "AwfulBrowserViewController.h"
#import "AwfulDataStack.h"
#import "AwfulDateFormatters.h"
#import "AwfulExternalBrowser.h"
#import "AwfulForumsClient.h"
#import "AwfulImagePreviewViewController.h"
#import "AwfulLoadingView.h"
#import "AwfulModels.h"
#import "AwfulNewPrivateMessageViewController.h"
#import "AwfulPrivateMessageViewModel.h"
#import "AwfulProfileViewController.h"
#import "AwfulRapSheetViewController.h"
#import "AwfulReadLaterService.h"
#import "AwfulSettings.h"
#import "AwfulUIKitAndFoundationCategories.h"
#import "AwfulTheme.h"
#import <AFNetworkActivityIndicatorManager.h>
#import <GRMustache/GRMustache.h>
#import <WebViewJavascriptBridge.h>

@interface AwfulPrivateMessageViewController () <UIWebViewDelegate, AwfulComposeTextViewControllerDelegate, UIGestureRecognizerDelegate, UIViewControllerRestoration>

@property (strong, nonatomic) AwfulPrivateMessage *privateMessage;

@property (readonly, strong, nonatomic) UIWebView *webView;

@property (strong, nonatomic) AwfulLoadingView *loadingView;

@property (strong, nonatomic) UIBarButtonItem *actionButtonItem;

@end

@implementation AwfulPrivateMessageViewController
{
    WebViewJavascriptBridge *_webViewJavaScriptBridge;
    NSUInteger _webViewActiveRequestCount;
    AwfulNewPrivateMessageViewController *_composeViewController;
    BOOL _didRender;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (_webViewActiveRequestCount > 0) {
        [[AFNetworkActivityIndicatorManager sharedManager] decrementActivityCount];
    }
}

- (id)initWithPrivateMessage:(AwfulPrivateMessage *)privateMessage
{
    self = [super initWithNibName:nil bundle:nil];
    if (!self) return nil;
    
    _privateMessage = privateMessage;
    self.title = privateMessage.subject;
    self.navigationItem.rightBarButtonItem = self.actionButtonItem;
    self.navigationItem.backBarButtonItem = [UIBarButtonItem awful_emptyBackBarButtonItem];
    self.restorationClass = self.class;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(settingsDidChange:)
                                                 name:AwfulSettingsDidChangeNotification
                                               object:nil];
    
    return self;
}

- (void)renderMessage
{
    AwfulPrivateMessageViewModel *viewModel = [[AwfulPrivateMessageViewModel alloc] initWithPrivateMessage:self.privateMessage];
    viewModel.stylesheet = self.theme[@"postsViewCSS"];
    NSError *error;
    NSString *HTML = [GRMustacheTemplate renderObject:viewModel fromResource:@"PrivateMessage" bundle:nil error:&error];
    if (!HTML) {
        NSLog(@"%s error rendering private message: %@", __PRETTY_FUNCTION__, error);
    }
    NSURL *baseURL = [AwfulForumsClient client].baseURL;
    [self.webView loadHTMLString:HTML baseURL:baseURL];
    _didRender = YES;
}

- (UIBarButtonItem *)actionButtonItem
{
    if (_actionButtonItem) return _actionButtonItem;
    _actionButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                      target:self
                                                                      action:@selector(didTapActionButtonItem:)];
    return _actionButtonItem;
}

- (void)didTapActionButtonItem:(UIBarButtonItem *)buttonItem
{
    AwfulPrivateMessage *privateMessage = self.privateMessage;
    AwfulActionSheet *sheet = [AwfulActionSheet new];
    __weak __typeof__(self) weakSelf = self;
    
    [sheet addButtonWithTitle:@"Reply" block:^{
        [[AwfulForumsClient client] quoteBBcodeContentsOfPrivateMessage:privateMessage andThen:^(NSError *error, NSString *BBcode) {
            __typeof__(self) self = weakSelf;
            if (error) {
                [AwfulAlertView showWithTitle:@"Could Not Quote Message" error:error buttonTitle:@"OK"];
            } else {
                _composeViewController = [[AwfulNewPrivateMessageViewController alloc] initWithRegardingMessage:privateMessage
                                                                                                initialContents:BBcode];
                _composeViewController.delegate = self;
                _composeViewController.restorationIdentifier = @"New private message replying to private message";
                [self presentViewController:[_composeViewController enclosingNavigationController] animated:YES completion:nil];
            }
        }];
    }];
    
    [sheet addButtonWithTitle:@"Forward" block:^{
        [[AwfulForumsClient client] quoteBBcodeContentsOfPrivateMessage:self.privateMessage andThen:^(NSError *error, NSString *BBcode) {
            __typeof__(self) self = weakSelf;
            if (error) {
                [AwfulAlertView showWithTitle:@"Could Not Quote Message" error:error buttonTitle:@"OK"];
            } else {
                _composeViewController = [[AwfulNewPrivateMessageViewController alloc] initWithForwardingMessage:self.privateMessage
                                                                                                 initialContents:BBcode];
                _composeViewController.delegate = self;
                _composeViewController.restorationIdentifier = @"New private message forwarding private message";
                [self presentViewController:[_composeViewController enclosingNavigationController] animated:YES completion:nil];
            }
        }];
    }];
    
    [sheet addCancelButtonWithTitle:@"Cancel"];
    [sheet showFromBarButtonItem:buttonItem animated:YES];
}

- (void)showUserActionsFromRect:(CGRect)rect
{
	AwfulActionViewController *sheet = [AwfulActionViewController new];
    AwfulUser *user = self.privateMessage.from;
    
	[sheet addItem:[AwfulIconActionItem itemWithType:AwfulIconActionItemTypeUserProfile action:^{
        AwfulProfileViewController *profile = [[AwfulProfileViewController alloc] initWithUser:user];
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
            [self presentViewController:[profile enclosingNavigationController] animated:YES completion:nil];
        } else {
            [self.navigationController pushViewController:profile animated:YES];
        }
	}]];
    
	[sheet addItem:[AwfulIconActionItem itemWithType:AwfulIconActionItemTypeRapSheet action:^{
        AwfulRapSheetViewController *rapSheet = [[AwfulRapSheetViewController alloc] initWithUser:user];
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
            [self presentViewController:[rapSheet enclosingNavigationController] animated:YES completion:nil];
        } else {
            [self.navigationController pushViewController:rapSheet animated:YES];
        }
	}]];
    
    AwfulSemiModalRectInViewBlock headerBlock = ^(UIView *view) {
        CGRect rect = CGRectFromString([self.webView awful_evalJavaScript:@"HeaderRect()"]);
        UIEdgeInsets insets = self.webView.scrollView.contentInset;
        return CGRectOffset(rect, insets.left, insets.top);
    };
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        [sheet presentInPopoverFromView:self.view pointingToRegionReturnedByBlock:headerBlock];
    } else {
        [sheet presentFromView:self.view highlightingRegionReturnedByBlock:headerBlock];
    }
}

- (void)didLongPressWebView:(UILongPressGestureRecognizer *)sender
{
    if (sender.state == UIGestureRecognizerStateBegan) {
        CGPoint location = [sender locationInView:self.webView];
        CGFloat offsetY = self.webView.scrollView.contentOffset.y;
        if (offsetY < 0) {
            location.y += offsetY;
        }
        NSDictionary *data = @{ @"x": @(location.x), @"y": @(location.y) };
        [_webViewJavaScriptBridge callHandler:@"interestingElementsAtPoint" data:data responseCallback:^(NSDictionary *response) {
            if (response.count == 0) return;
            
            NSURL *imageURL = [NSURL URLWithString:response[@"spoiledImageURL"] relativeToURL:[AwfulForumsClient client].baseURL];
            if (response[@"spoiledLink"]) {
                NSDictionary *linkInfo = response[@"spoiledLink"];
                NSURL *URL = [NSURL URLWithString:linkInfo[@"URL"] relativeToURL:[AwfulForumsClient client].baseURL];
                UIEdgeInsets insets = self.webView.scrollView.contentInset;
                CGRect rect = CGRectOffset(CGRectFromString(linkInfo[@"rect"]), insets.left, insets.top);
                [self showMenuForLinkToURL:URL fromRect:rect withImageURL:imageURL];
            } else if (imageURL) {
                [self previewImageAtURL:imageURL];
            } else if (response[@"spoiledVideo"]) {
                NSDictionary *videoInfo = response[@"spoiledVideo"];
                NSURL *URL = [NSURL URLWithString:videoInfo[@"URL"] relativeToURL:[AwfulForumsClient client].baseURL];
                UIEdgeInsets insets = self.webView.scrollView.contentInset;
                CGRect rect = CGRectOffset(CGRectFromString(videoInfo[@"rect"]), insets.left, insets.top);
                [self showMenuForVideoAtURL:URL fromRect:rect];
            } else {
                NSLog(@"%s unexpected interesting elements for data %@ response: %@", __PRETTY_FUNCTION__, data, response);
            }
        }];
    }
}

- (void)showMenuForLinkToURL:(NSURL *)URL fromRect:(CGRect)rect withImageURL:(NSURL *)imageURL
{
    if ([URL opensInBrowser] || imageURL) {
        AwfulActionSheet *sheet = [AwfulActionSheet new];
        
        if ([URL opensInBrowser]) {
            sheet.title = URL.absoluteString;
        
            [sheet addButtonWithTitle:@"Open" block:^{
                NSURL *awfulURL = URL.awfulURL;
                if (awfulURL) {
                    [[AwfulAppDelegate instance] openAwfulURL:awfulURL];
                } else {
                    [AwfulBrowserViewController presentBrowserForURL:URL fromViewController:self];
                }
            }];
            
            [sheet addButtonWithTitle:@"Open in Safari" block:^{ [[UIApplication sharedApplication] openURL:URL]; }];
            
            for (AwfulExternalBrowser *browser in [AwfulExternalBrowser installedBrowsers]) {
                if (![browser canOpenURL:URL]) continue;
                [sheet addButtonWithTitle:[NSString stringWithFormat:@"Open in %@", browser.title]
                                    block:^{ [browser openURL:URL]; }];
            }
            
            for (AwfulReadLaterService *service in [AwfulReadLaterService availableServices]) {
                [sheet addButtonWithTitle:service.callToAction block:^{
                    [service saveURL:URL];
                }];
            }
            
            [sheet addButtonWithTitle:@"Copy URL" block:^{
                [UIPasteboard generalPasteboard].awful_URL = URL;
            }];
        } else {
            [sheet addButtonWithTitle:@"Open" block:^{ [[UIApplication sharedApplication] openURL:URL]; }];
        }
        
        if (imageURL) {
            [sheet addButtonWithTitle:@"Show Image" block:^{ [self previewImageAtURL:imageURL]; }];
        }
        
        [sheet addCancelButtonWithTitle:@"Cancel"];
        [sheet showFromRect:rect inView:self.view animated:YES];
    } else {
        [[UIApplication sharedApplication] openURL:URL];
    }
}

- (void)showMenuForVideoAtURL:(NSURL *)URL fromRect:(CGRect)rect
{
    NSURLComponents *components = [NSURLComponents new];
    if ([URL.host hasSuffix:@"youtube-nocookie.com"]) {
        components.scheme = @"http";
        components.host = @"www.youtube.com";
        components.path = @"/watch";
        components.query = [@"v=" stringByAppendingString:URL.lastPathComponent];
    } else if ([URL.host hasSuffix:@"player.vimeo.com"]) {
        components.scheme = @"http";
        components.host = @"vimeo.com";
        components.path = [@"/" stringByAppendingString:URL.lastPathComponent];
    } else {
        return;
    }
    
    AwfulActionSheet *sheet = [AwfulActionSheet new];
    [sheet addButtonWithTitle:@"Open" block:^{
        [AwfulBrowserViewController presentBrowserForURL:components.URL fromViewController:self];
    }];
    
    void (^openInSafariOrYouTube)(void) = ^{ [[UIApplication sharedApplication] openURL:components.URL]; };
    if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"youtube://"]]) {
        [sheet addButtonWithTitle:@"Open in YouTube" block:openInSafariOrYouTube];
    } else {
        [sheet addButtonWithTitle:@"Open in Safari" block:openInSafariOrYouTube];
    }
    
    [sheet addCancelButtonWithTitle:@"Cancel"];
    [sheet showFromRect:rect inView:self.view animated:YES];
}

- (void)previewImageAtURL:(NSURL *)url
{
    AwfulImagePreviewViewController *preview = [[AwfulImagePreviewViewController alloc] initWithURL:url];
    preview.title = self.title;
    UINavigationController *nav = [preview enclosingNavigationController];
    nav.navigationBar.translucent = YES;
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)settingsDidChange:(NSNotification *)note
{
    if (![self isViewLoaded]) return;
    
    NSString *changedSetting = note.userInfo[AwfulSettingsDidChangeSettingKey];
    if ([changedSetting isEqualToString:AwfulSettingsKeys.showAvatars]) {
        [_webViewJavaScriptBridge callHandler:@"showAvatars" data:@([AwfulSettings settings].showAvatars)];
    } else if ([changedSetting isEqualToString:AwfulSettingsKeys.showImages]) {
        if ([AwfulSettings settings].showImages) {
            [_webViewJavaScriptBridge callHandler:@"loadLinkifiedImages"];
        }
    }
}

- (UIWebView *)webView
{
    return (UIWebView *)self.view;
}

- (void)loadView
{
    self.view = [UIWebView awful_nativeFeelingWebView];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _webViewJavaScriptBridge = [WebViewJavascriptBridge bridgeForWebView:self.webView webViewDelegate:self handler:^(id data, WVJBResponseCallback _) {
        NSLog(@"%s %@", __PRETTY_FUNCTION__, data);
    }];
    __weak __typeof__(self) weakSelf = self;
    [_webViewJavaScriptBridge registerHandler:@"didTapUserHeader" handler:^(NSString *rectString, WVJBResponseCallback responseCallback) {
        __typeof__(self) self = weakSelf;
        UIEdgeInsets insets = self.webView.scrollView.contentInset;
        CGRect rect = CGRectOffset(CGRectFromString(rectString), insets.left, insets.top);
        [self showUserActionsFromRect:rect];
    }];
    
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(didLongPressWebView:)];
    longPress.delegate = self;
    [self.webView addGestureRecognizer:longPress];
    
    if (self.privateMessage.innerHTML.length == 0) {
        self.loadingView = [AwfulLoadingView loadingViewForTheme:self.theme];
        self.loadingView.message = @"Loading…";
        [self.view addSubview:self.loadingView];
        __weak __typeof__(self) weakSelf = self;
        [[AwfulForumsClient client] readPrivateMessage:self.privateMessage andThen:^(NSError *error) {
            __typeof__(self) self = weakSelf;
            self.title = self.privateMessage.subject;
            [self renderMessage];
            [self.loadingView removeFromSuperview];
            self.loadingView = nil;
        }];
    } else {
        [self renderMessage];
    }
}

- (void)themeDidChange
{
    [super themeDidChange];
    AwfulTheme *theme = self.theme;
    if (_didRender) {
        [_webViewJavaScriptBridge callHandler:@"changeStylesheet" data:theme[@"postsViewCSS"]];
    }
    self.view.backgroundColor = theme[@"backgroundColor"];
    self.webView.scrollView.indicatorStyle = theme.scrollIndicatorStyle;
    self.loadingView.tintColor = theme[@"backgroundColor"];
}

#pragma mark - UIWebViewDelegate

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    NSURL *URL = request.URL;
    
    // Tapping the title of an embedded YouTube video doesn't come through as a click. It'll just take over the web view if we're not careful.
    if ([URL.host.lowercaseString hasSuffix:@"www.youtube.com"] && [URL.path.lowercaseString hasPrefix:@"/watch"]) {
        navigationType = UIWebViewNavigationTypeLinkClicked;
    }
    
    if (navigationType == UIWebViewNavigationTypeLinkClicked) {
        NSURL *awfulURL = URL.awfulURL;
        if (awfulURL) {
            [[AwfulAppDelegate instance] openAwfulURL:awfulURL];
        } else if ([URL opensInBrowser]) {
            [AwfulBrowserViewController presentBrowserForURL:URL fromViewController:self];
        } else {
            [[UIApplication sharedApplication] openURL:URL];
        }
        return NO;
    }
    
    return YES;
}

- (void)webViewDidStartLoad:(UIWebView *)webView
{
    ++_webViewActiveRequestCount;
    if (_webViewActiveRequestCount == 1) {
        [[AFNetworkActivityIndicatorManager sharedManager] incrementActivityCount];
    }
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    --_webViewActiveRequestCount;
    if (_webViewActiveRequestCount == 0) {
        [[AFNetworkActivityIndicatorManager sharedManager] decrementActivityCount];
    }
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    --_webViewActiveRequestCount;
    if (_webViewActiveRequestCount == 0) {
        [[AFNetworkActivityIndicatorManager sharedManager] decrementActivityCount];
    }
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer
{
    return YES;
}

#pragma mark - AwfulComposeTextViewControllerDelegate

- (void)composeTextViewController:(AwfulComposeTextViewController *)composeTextViewController
didFinishWithSuccessfulSubmission:(BOOL)success
                  shouldKeepDraft:(BOOL)keepDraft
{
    [self dismissViewControllerAnimated:YES completion:nil];
    _composeViewController = nil;
}

#pragma mark State preservation and restoration

+ (UIViewController *)viewControllerWithRestorationIdentifierPath:(NSArray *)identifierComponents coder:(NSCoder *)coder
{
    NSString *messageID = [coder decodeObjectForKey:MessageIDKey];
    AwfulPrivateMessage *privateMessage = [AwfulPrivateMessage fetchArbitraryInManagedObjectContext:[AwfulAppDelegate instance].managedObjectContext
                                                                            matchingPredicateFormat:@"messageID = %@", messageID];
    AwfulPrivateMessageViewController *messageViewController = [[self alloc] initWithPrivateMessage:privateMessage];
    messageViewController.restorationIdentifier = identifierComponents.lastObject;
    return messageViewController;
}

- (void)encodeRestorableStateWithCoder:(NSCoder *)coder
{
    [super encodeRestorableStateWithCoder:coder];
    [coder encodeObject:self.privateMessage.messageID forKey:MessageIDKey];
    [coder encodeObject:_composeViewController forKey:ComposeViewControllerKey];
}

- (void)decodeRestorableStateWithCoder:(NSCoder *)coder
{
    [super decodeRestorableStateWithCoder:coder];
    _composeViewController = [coder decodeObjectForKey:ComposeViewControllerKey];
    _composeViewController.delegate = self;
}

static NSString * const MessageIDKey = @"AwfulMessageID";
static NSString * const ComposeViewControllerKey = @"AwfulComposeViewController";

@end
