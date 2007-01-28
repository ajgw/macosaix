//
//  MacOSaiXExportController.h
//  MacOSaiX
//
//  Created by Frank Midgley on 2/4/06.
//  Copyright 2006 Frank M. Midgley. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@class MacOSaiXMosaic, MacOSaiXProgressController, MosaicView;


@interface MacOSaiXExportController : NSWindowController
{
    IBOutlet NSView				*accessoryView;
	
	IBOutlet MosaicView			*mosaicView;
	IBOutlet NSSlider			*fadeSlider;
	
	IBOutlet NSMatrix			*formatMatrix;
	IBOutlet NSButton			*createWebPageButton, 
								*includeTargetButton;
	
	IBOutlet NSTextField		*widthField, 
								*heightField;
	IBOutlet NSPopUpButton		*unitsPopUp, 
								*resolutionPopUp;
	
	IBOutlet NSButton			*openWhenCompleteButton;
	
	MacOSaiXMosaic				*mosaic;
	id							delegate;
	SEL							didEndSelector;
	
	MacOSaiXProgressController	*progressController;
	
    int							imageFormat;
	BOOL						createWebPage, 
								includeTargetImage, 
								openWhenComplete, 
								exportCancelled;
	
	unsigned char				*bitmapBuffer;
}

- (void)exportMosaic:(MacOSaiXMosaic *)mosaic
			withName:(NSString *)name 
		  mosaicView:(MosaicView *)inMosaicView 
	  modalForWindow:(NSWindow *)window 
	   modalDelegate:(id)inDelegate
	  didEndSelector:(SEL)inDidEndSelector;

- (IBAction)setFade:(id)sender;

- (IBAction)setUnits:(id)sender;
- (IBAction)setResolution:(id)sender;

- (IBAction)setImageFormat:(id)sender;
- (IBAction)setCreateWebPage:(id)sender;
- (IBAction)setIncludeTargetImage:(id)sender;

- (IBAction)setOpenImageWhenComplete:(id)sender;

- (IBAction)cancelExport:(id)sender;

- (NSString *)exportFormat;

@end
