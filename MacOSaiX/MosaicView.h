//
//  MosaicView.h
//  MacOSaiX
//
//  Created by Frank Midgley on Sat Feb 02 2002.
//  Copyright (c) 2001-5 Frank M. Midgley.  All rights reserved.
//

@class MacOSaiXMosaic, MacOSaiXTile, MacOSaiXEditorsView;


@interface MosaicView : NSView
{
	MacOSaiXMosaic			*mosaic;
	NSImage					*mainImage;
	NSSize					mainImageSize;
	NSLock					*mainImageLock;
	NSAffineTransform		*mainImageTransform;
	BOOL					inLiveRedraw;
	
		// Target image transition
	NSImage					*previousTargetImage;
	NSDate					*targetFadeStartTime;
	NSTimer					*targetFadeTimer;
	float					targetFadeTime;
	
		// Target image opacity animation
	float					targetImageOpacity, 
							previousTargetImageOpacity, 
							opacityChangeDuration;
	NSDate					*opacityChangeStartTime;
	NSTimer					*opacityChangeTimer;
	
	MacOSaiXEditorsView		*editorsView;
	
	NSColor					*backgroundColor;
	
	BOOL					showNonUniqueMatches;
	
	IBOutlet NSMenu			*contextualMenu;
	
		// Tile refreshing
	NSMutableArray			*tilesToRefresh;
	NSLock					*tileRefreshLock;
	BOOL					refreshingTiles;
	
		// Queued tile view invalidation
	NSMutableArray			*tilesNeedingDisplay;
	NSLock					*tilesNeedDisplayLock;
	NSTimer					*tilesNeedDisplayTimer;
	
		// Custom tooltip window
	NSTimer					*tooltipTimer, 
							*tooltipHideTimer;
	IBOutlet NSWindow		*tooltipWindow;
	IBOutlet NSImageView	*tileImageView, 
							*imageSourceImageView;
	IBOutlet NSTextField	*imageSourceTextField, 
							*tileImageTextField;
	MacOSaiXTile			*tooltipTile;
}

- (void)setMosaic:(MacOSaiXMosaic *)inMosaic;
- (MacOSaiXMosaic *)mosaic;

- (void)setEditorsView:(MacOSaiXEditorsView *)view;
- (MacOSaiXEditorsView *)editorsView;

- (void)setBackgroundColor:(NSColor *)color;
- (NSColor *)backgroundColor;

- (NSRect)imageBounds;

- (void)setMainImage:(NSImage *)image;
- (NSImage *)mainImage;

- (void)setTargetImageOpacity:(float)fraction animationTime:(float)seconds;
- (float)targetImageOpacity;

- (void)setTargetFadeTime:(float)seconds;

- (void)setInLiveRedraw:(NSNumber *)flag;
- (BOOL)inLiveRedraw;

- (MacOSaiXTile *)tileAtPoint:(NSPoint)thePoint;
- (NSArray *)tilesInRect:(NSRect)theRect;

- (NSImage *)image;

- (BOOL)isBusy;
- (NSString *)busyStatus;

@end


// Notifications
extern NSString	*MacOSaiXMosaicViewDidChangeBusyStateNotification;
extern NSString *MacOSaiXMosaicViewDidChangeTargetImageOpacityNotification;
