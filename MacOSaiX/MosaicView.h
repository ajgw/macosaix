//
//  MosaicView.h
//  MacOSaiX
//
//  Created by Frank Midgley on Sat Feb 02 2002.
//  Copyright (c) 2001-5 Frank M. Midgley.  All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MacOSaiXMosaic.h"
#import "Tiles.h"


typedef enum { clearMode = 0, blackMode, originalMode, bestMatchMode } MacOSaiXBackgroundMode;


@interface MosaicView : NSView
{
	MacOSaiXMosaic			*mosaic;
	NSImage					*mainImage, 
							*backgroundImage;
	NSSize					mainImageSize;
	NSLock					*mainImageLock, 
							*backgroundImageLock;
	NSAffineTransform		*mainImageTransform;
	float					viewFade, 
							originalFadeTime;
	BOOL					inLiveRedraw;
	
		// Original image fading
	NSImage					*previousOriginalImage;
	NSDate					*originalFadeStartTime;
	NSTimer					*originalFadeTimer;
	
		// Tile outlines display
	BOOL					viewTileOutlines;
	NSImage					*tileOutlinesImage;
					
		// Selected tile highlighting
    MacOSaiXTile			*highlightedTile;
	NSArray					*highlightedImageSources;
	NSLock					*highlightedImageSourcesLock;
	NSBezierPath			*highlightedImageSourcesOutline;
	NSTimer					*animateHighlightedTileTimer;
    int						phase;
	
	IBOutlet NSMenu			*contextualMenu;
	
		// Tile refreshing
	NSMutableArray			*tilesToRefresh, 
							*tileMatchTypesToRefresh;
	NSLock					*tileRefreshLock;
	BOOL					refreshingTiles;
	
		// Queued tile view invalidation
	NSMutableArray			*tilesNeedingDisplay;
	NSLock					*tilesNeedDisplayLock;
	NSTimer					*tilesNeedDisplayTimer;
	
	MacOSaiXBackgroundMode	backgroundMode;
	
		// Custom tooltip window
	NSTimer					*tooltipTimer;
	IBOutlet NSWindow		*tooltipWindow;
	IBOutlet NSImageView	*tileImageView, 
							*imageSourceImageView;
	IBOutlet NSTextField	*imageSourceTextField, 
							*tileImageTextField;
	MacOSaiXTile			*tooltipTile;
}

- (void)setMosaic:(MacOSaiXMosaic *)inMosaic;

- (void)setMainImage:(NSImage *)image;
- (NSImage *)mainImage;
- (void)setBackgroundImage:(NSImage *)image;
- (NSImage *)backgroundImage;

- (void)setFade:(float)fade;
- (float)fade;

- (void)setOriginalFadeTime:(float)seconds;

- (void)setInLiveRedraw:(NSNumber *)flag;

- (void)setViewTileOutlines:(BOOL)inViewTileOutlines;
- (BOOL)viewTileOutlines;

- (void)setBackgroundMode:(MacOSaiXBackgroundMode)mode;
- (MacOSaiXBackgroundMode)backgroundMode;

	// Highlighting
- (void)setHighlightedTile:(MacOSaiXTile *)tile;
- (MacOSaiXTile *)highlightedTile;
- (void)highlightImageSources:(NSArray *)imageSources;

- (NSImage *)image;

@end
