/*
	MacOSaiXDocument.h
	MacOSaiX

	Created by Frank Midgley on Sun Oct 24 2004.
	Copyright (c) 2004 Frank M. Midgley. All rights reserved.
*/


#import "MacOSaiX.h"
#import "MacOSaiXDocument.h"
#import "MacOSaiXWindowController.h"
#import "MacOSaiXImageCache.h"
#import "Tiles.h"
#import "NSImage+MacOSaiX.h"


	// The maximum size of the image URL queue
#define MAXIMAGEURLS 4


	// Notifications
NSString	*MacOSaiXDocumentDidChangeStateNotification = @"MacOSaiXDocumentDidChangeStateNotification";
NSString	*MacOSaiXDocumentDidSaveNotification = @"MacOSaiXDocumentDidSaveNotification";
NSString	*MacOSaiXOriginalImageDidChangeNotification = @"MacOSaiXOriginalImageDidChangeNotification";
NSString	*MacOSaiXTileImageDidChangeNotification = @"MacOSaiXTileImageDidChangeNotification";
NSString	*MacOSaiXTileShapesDidChangeStateNotification = @"MacOSaiXTileShapesDidChangeStateNotification";


@interface MacOSaiXDocument (PrivateMethods)
- (void)addTile:(MacOSaiXTile *)tile;
- (void)spawnImageSourceThreads;
- (BOOL)started;
- (void)lockWhilePaused;
- (void)updateMosaicImage:(NSMutableArray *)updatedTiles;
- (void)calculateImageMatches:(id)path;
- (void)extractTileImagesFromOriginalImage:(id)object;
- (void)updateEditor;
- (BOOL)showTileMatchInEditor:(MacOSaiXImageMatch *)tileMatch selecting:(BOOL)selecting;
- (NSImage *)createEditorImage:(int)rowIndex;
@end


@implementation MacOSaiXDocument

- (id)init
{
    if (self = [super init])
    {
		[self setHasUndoManager:FALSE];	// don't track undo-able changes
		
		paused = YES;
		[self setTileShapes:[[[NSClassFromString(@"MacOSaiXRectangularTileShapes") alloc] init] autorelease]];
		imageSources = [[NSMutableArray arrayWithCapacity:0] retain];
		lastSaved = [[NSDate date] retain];
		autosaveFrequency = [[[NSUserDefaults standardUserDefaults] objectForKey:@"Autosave Frequency"] intValue];

		pauseLock = [[NSLock alloc] init];
		[pauseLock lock];
			
		// create the image URL queue and its lock
		imageQueue = [[NSMutableArray arrayWithCapacity:0] retain];
		imageQueueLock = [[NSLock alloc] init];

		calculateImageMatchesThreadLock = [[NSLock alloc] init];
		betterMatchesCache = [[NSMutableDictionary dictionary] retain];
		
		tileImages = [[NSMutableArray arrayWithCapacity:0] retain];
		tileImagesLock = [[NSLock alloc] init];
		
		enumerationThreadCountLock = [[NSLock alloc] init];
		enumerationCountsLock = [[NSLock alloc] init];
		enumerationCounts = [[NSMutableDictionary dictionary] retain];
		
		[self setNeighborhoodSize:5];
	}
	
    return self;
}


- (void)makeWindowControllers
{
	MacOSaiXWindowController	*controller = [[[MacOSaiXWindowController alloc] initWithWindowNibName:@"MacOSaiXDocument"] autorelease];
	
	[self addWindowController:controller];
	[controller showWindow:self];
}


//- (void)shouldCloseWindowController:(NSWindowController *)windowController 
//						   delegate:(id)delegate 
//				shouldCloseSelector:(SEL)callback 
//						contextInfo:(void *)contextInfo
//{
//	if (saving)
//	{
//		if (delegate && [delegate respondsToSelector:callback])
//		{
//				// ...
//				// The delegate's selector has the signature:
//				// - (void)document:(NSDocument *)doc didSave:(BOOL)didSave contextInfo:(void *)contextInfo
//			NSMethodSignature	*signature = [[delegate class] instanceMethodSignatureForSelector:callback];
//			NSInvocation		*shouldCloseCallback = [NSInvocation invocationWithMethodSignature:signature];
//			BOOL				shouldClose = NO;
//			
//			[shouldCloseCallback setTarget:delegate];
//			[shouldCloseCallback setSelector:callback];
//			[shouldCloseCallback setArgument:&self atIndex:2];
//			[shouldCloseCallback setArgument:&shouldClose atIndex:3];
//			[shouldCloseCallback setArgument:&contextInfo atIndex:4];
//			[shouldCloseCallback invoke];
//		}
//	}
//	else
//		[super shouldCloseWindowController:windowController 
//								  delegate:delegate 
//					   shouldCloseSelector:callback 
//							   contextInfo:contextInfo];
//}


//- (void)removeWindowController:(NSWindowController *)windowController
//{
//	if (saving)
//		;
//	else
//		[super removeWindowController:windowController];
//}


- (void)setOriginalImagePath:(NSString *)path
{
	if (![path isEqualToString:originalImagePath])
	{
		[originalImagePath release];
		[originalImage release];
		
		originalImagePath = [[NSString stringWithString:path] retain];
		originalImage = [[NSImage alloc] initWithContentsOfFile:path];
		[originalImage setCachedSeparately:YES];
//		[originalImage setCacheMode:NSImageCacheNever];

			// Ignore whatever DPI was set for the image.  We just care about the bitmap.
		NSImageRep	*originalRep = [[originalImage representations] objectAtIndex:0];
		[originalRep setSize:NSMakeSize([originalRep pixelsWide], [originalRep pixelsHigh])];
		[originalImage setSize:NSMakeSize([originalRep pixelsWide], [originalRep pixelsHigh])];
		
		[[NSNotificationCenter defaultCenter] postNotificationName:MacOSaiXOriginalImageDidChangeNotification object:self];
	}
}


- (NSString *)originalImagePath
{
	return originalImagePath;
}


- (NSImage *)originalImage
{
	return [[originalImage retain] autorelease];
}


#pragma mark -
#pragma mark Pausing/resuming


- (BOOL)wasStarted
{
	return mosaicStarted;
}


- (BOOL)isPaused
{
	return paused;
}


- (void)pause
{
	if (!paused)
	{
			// Wait for the one-shot startup thread to end.
		while ([self isExtractingTileImagesFromOriginal])
			[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];

			// Tell the enumeration threads to stop sending in any new images.
		[pauseLock lock];
		
			// Wait for any queued images to get processed.
			// TBD: can we condition lock here instead of poll?
			// TBD: this could block the main thread
		while ([self isCalculatingImageMatches])
			[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
		
		paused = YES;
		
		[[NSNotificationCenter defaultCenter] postNotificationName:MacOSaiXDocumentDidChangeStateNotification object:self];
	}
}


- (void)lockWhilePaused
{
	[pauseLock lock];
	[pauseLock unlock];
}


- (void)resume
{
	if (paused)
	{
		if ([[tiles objectAtIndex:0] bitmapRep] == nil)
		{
				// Automatically start the mosaic.
				// Show the mosaic image and start extracting the tile images.
			if ([[self windowControllers] count] > 0)
				[[[self windowControllers] objectAtIndex:0] setViewMosaic:self];
			[NSApplication detachDrawingThread:@selector(extractTileImagesFromOriginalImage)
									  toTarget:self
									withObject:nil];
		}
		else
		{
				// Start or restart the image sources
			[pauseLock unlock];
			
			paused = NO;
			mosaicStarted = YES;
			
			[[NSNotificationCenter defaultCenter] postNotificationName:MacOSaiXDocumentDidChangeStateNotification object:self];
		}
	}
}


#pragma mark -
#pragma mark Save and Open methods


- (BOOL)isSaving
{
	return saving;
}


- (void)setIsSaving:(BOOL)isSaving
{
	saving = isSaving;
}


- (BOOL)prepareSavePanel:(NSSavePanel *)savePanel
{
	[savePanel setRequiredFileType:@"mosaic"];
	return YES;
}


- (void)saveToFile:(NSString *)fileName 
	 saveOperation:(NSSaveOperationType)saveOperation 
		  delegate:(id)delegate 
   didSaveSelector:(SEL)didSaveSelector 
	   contextInfo:(void *)contextInfo;
{
	if (!fileName)
		return;	// the user cancelled the save
	
	[self setIsSaving:YES];
	
	BOOL			wasPaused = paused;
	
		// Pause the mosaic so that it is in a static state while saving.
	[self pause];
	
		// Display a sheet while the save is underway
	[[[self windowControllers] objectAtIndex:0] displayProgressPanelWithMessage:@"Saving..."];
// TODO:	[[[self windowControllers] objectAtIndex:0] setCancelAction:@selector(cancelSave) andTarget:self];
	
	NSMutableDictionary	*parameters = [NSMutableDictionary dictionaryWithObjectsAndKeys:
											fileName, @"Save Path", 
											[NSNumber numberWithInt:saveOperation], @"Save Operation", 
											[NSNumber numberWithBool:wasPaused], @"Was Paused", 
											nil];
	if (delegate)
		[parameters setObject:delegate forKey:@"Did Save Delegate"];
	if (didSaveSelector)
		[parameters setObject:NSStringFromSelector(didSaveSelector) forKey:@"Did Save Selector"];
	if (contextInfo)
		[parameters setObject:[NSNumber numberWithUnsignedLong:(unsigned long)contextInfo] forKey:@"Context Info"];
	
	[NSThread detachNewThreadSelector:@selector(threadedSaveWithParameters:) 
							 toTarget:self 
						   withObject:parameters];
}


- (BOOL)writeToFile:(NSString *)fullDocumentPath 
			 ofType:(NSString *)docType 
	   originalFile:(NSString *)fullOriginalDocumentPath 
	  saveOperation:(NSSaveOperationType)saveOperationType
{
	[self setIsSaving:YES];
	
	BOOL			wasPaused = paused;
	
		// Pause the mosaic so that it is in a static state while saving.
	[self pause];
	
	[[[self windowControllers] objectAtIndex:0] displayProgressPanelWithMessage:@"Saving..."];

	NSMutableDictionary	*parameters = [NSMutableDictionary dictionaryWithObjectsAndKeys:
											fullDocumentPath, @"Save Path", 
											[NSNumber numberWithInt:saveOperationType], @"Save Operation", 
											[NSNumber numberWithBool:wasPaused], @"Was Paused", 
											nil];
	[NSThread detachNewThreadSelector:@selector(threadedSaveWithParameters:) 
							 toTarget:self 
						   withObject:parameters];

	return YES;
}


- (void)cancelSave
{
	// TODO
}


- (NSString *)indexAsAlpha:(int)index
{
	char	buffer[8] = {0, 0, 0, 0, 0, 0, 0, 0};
	char	*p = &buffer[6];
	
	do
	{
		*p-- = (index % 26) + 65;
		index /= 26;
	}
	while (index != 0);
	
	return [NSString stringWithCString:++p];
}


- (NSDictionary *)imagesInUse
{
	NSMutableDictionary	*imagesInUse = [NSMutableDictionary dictionary];
	NSEnumerator		*tileEnumerator = [tiles objectEnumerator];
	MacOSaiXTile		*tile = nil;
	while (tile = [tileEnumerator nextObject])
	{
		NSEnumerator		*matchEnumerator = [[NSArray arrayWithObjects:[tile imageMatch], [tile userChosenImageMatch], nil] 
																objectEnumerator];
		MacOSaiXImageMatch	*match = nil;
		while (match = [matchEnumerator nextObject])
		{
			NSString			*imageSourceID = [self indexAsAlpha:[imageSources indexOfObjectIdenticalTo:[match imageSource]]];
			NSMutableDictionary	*imageSourceImageDict = [imagesInUse objectForKey:imageSourceID];
			if (!imageSourceImageDict)
			{
				imageSourceImageDict = [NSMutableDictionary dictionary];
				[imagesInUse setObject:imageSourceImageDict forKey:imageSourceID];
			}
			NSString	*identifier = [match imageIdentifier];
			NSNumber	*imageID= [imageSourceImageDict objectForKey:identifier];
			if (!imageID)
			{
				imageID = [NSNumber numberWithLong:[imageSourceImageDict count]];
				[imageSourceImageDict setObject:imageID forKey:identifier];
			}
		}
	}
	
	return [NSDictionary dictionaryWithDictionary:imagesInUse];
}


- (void)threadedSaveWithParameters:(NSDictionary *)parameters
{
	NSAutoreleasePool	*pool = [[NSAutoreleasePool alloc] init];
	BOOL				saveSucceeded = NO;
	NSString			*savePath = [parameters objectForKey:@"Save Path"];
	NSSaveOperationType	saveOperation = [[parameters objectForKey:@"Save Operation"] intValue];
	id					didSaveDelegate = [parameters objectForKey:@"Did Save Delegate"];
	SEL					didSaveSelector = NSSelectorFromString([parameters objectForKey:@"Did Save Selector"]);
	void				*contextInfo = (void *)[[parameters objectForKey:@"Context Info"] unsignedLongValue];
	BOOL				wasPaused = [[parameters objectForKey:@"Was Paused"] boolValue];
	
	NSLog(@"Beginning save");
	
	NS_DURING
		// TODO: take the save operation into account

			// Don't usurp the main thread.
		[NSThread setThreadPriority:0.1];
		
			// Create the wrapper directory if it doesn't already exist.
		NSFileManager	*fileManager = [NSFileManager defaultManager];
		BOOL			isDir;
		if (([fileManager fileExistsAtPath:savePath isDirectory:&isDir] && isDir) || 
			[fileManager createDirectoryAtPath:savePath attributes:nil])
		{
					// Create the master save file in XML format.
			NSString	*xmlPath = [savePath stringByAppendingPathComponent:@"Mosaic.xml"];
			if (![[NSFileManager defaultManager] createFileAtPath:xmlPath contents:nil attributes:nil])
			{
				// TODO
			}
			else
			{
				NSFileHandle	*fileHandle = [NSFileHandle fileHandleForWritingAtPath:xmlPath];
				
					// Write out the XML header.
				[fileHandle writeData:[@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" dataUsingEncoding:NSUTF8StringEncoding]];
				[fileHandle writeData:[@"<!DOCTYPE plist PUBLIC \"-//Frank M. Midgley//DTD MacOSaiX 1.0//EN\" \"http://homepage.mac.com/knarf/DTDs/MacOSaiX-1.0.dtd\">\n\n" dataUsingEncoding:NSUTF8StringEncoding]];

				[fileHandle writeData:[@"<MOSAIC>\n\n" dataUsingEncoding:NSUTF8StringEncoding]];

					// Write out the path to the original image
				[fileHandle writeData:[[NSString stringWithFormat:@"<ORIGINAL_IMAGE PATH=\"%@\"/>\n\n", [self originalImagePath]] dataUsingEncoding:NSUTF8StringEncoding]];
				
					// Write out the tile shapes settings
				NSString		*className = NSStringFromClass([tileShapes class]);
				NSMutableString	*tileShapesXML = [NSMutableString stringWithString:
																[[tileShapes settingsAsXMLElement] stringByTrimmingCharactersInSet:
																	[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
				[tileShapesXML replaceOccurrencesOfString:@"\n" withString:@"\n\t" options:0 range:NSMakeRange(0, [tileShapesXML length])];
				[tileShapesXML insertString:@"\t" atIndex:0];
				[tileShapesXML appendString:@"\n"];
				[fileHandle writeData:[[NSString stringWithFormat:@"<TILE_SHAPES_SETTINGS CLASS=\"%@\">\n", className] dataUsingEncoding:NSUTF8StringEncoding]];
				[fileHandle writeData:[tileShapesXML dataUsingEncoding:NSUTF8StringEncoding]];
				[fileHandle writeData:[@"</TILE_SHAPES_SETTINGS>\n\n" dataUsingEncoding:NSUTF8StringEncoding]];
				
				[fileHandle writeData:[@"<IMAGE_USAGE>\n" dataUsingEncoding:NSUTF8StringEncoding]];
				[fileHandle writeData:[[NSString stringWithFormat:@"\t<IMAGE_REUSE COUNT=\"%d\" DISTANCE=\"%d\"/>\n", [self imageUseCount], [self neighborhoodSize]] dataUsingEncoding:NSUTF8StringEncoding]];
				[fileHandle writeData:[@"</IMAGE_USAGE>\n\n" dataUsingEncoding:NSUTF8StringEncoding]];
				
//				NSDictionary	*imagesInUse = [self imagesInUse];
				
					// Write out the cached images
//				[fileHandle writeData:[[imageCache xmlDataWithImageSources:imageSources] dataUsingEncoding:NSUTF8StringEncoding]];
//				if (![cachedImagesPath hasPrefix:fileName])
//				{
//						// This is the first time this mosaic has been saved so move 
//						// the image cache directory from /tmp to the new location.
//					NSString	*savedCachedImagesPath = [fileName stringByAppendingPathComponent:@"Cached Images"];
//					[fileManager movePath:cachedImagesPath toPath:savedCachedImagesPath handler:nil];
//					[cachedImagesPath autorelease];
//					cachedImagesPath = [savedCachedImagesPath retain];
//				}
				
					// Write out the image sources.
				[fileHandle writeData:[@"<IMAGE_SOURCES>\n" dataUsingEncoding:NSUTF8StringEncoding]];
				int	index;
				for (index = 0; index < [imageSources count]; index++)
				{
					id<MacOSaiXImageSource>	imageSource = [imageSources objectAtIndex:index];
					NSString				*className = NSStringFromClass([imageSource class]);
					[fileHandle writeData:[[NSString stringWithFormat:@"\t<IMAGE_SOURCE ID=\"%d\" CLASS=\"%@\">\n", 
																	  index, className] 
												dataUsingEncoding:NSUTF8StringEncoding]];
					
						// Output the settings for this image source.
						// TODO: need to tag this element with the source's namespace
					NSMutableString			*imageSourceXML = [NSMutableString stringWithString:
																[[imageSource settingsAsXMLElement] stringByTrimmingCharactersInSet:
																	[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
					[imageSourceXML replaceOccurrencesOfString:@"\n" withString:@"\n\t\t" options:0 range:NSMakeRange(0, [imageSourceXML length])];
					[imageSourceXML insertString:@"\t\t" atIndex:0];
					[imageSourceXML appendString:@"\n"];
					[fileHandle writeData:[imageSourceXML dataUsingEncoding:NSUTF8StringEncoding]];
					
						// Output an element for each image ID
//					[fileHandle writeData:[@"\t\t<IMAGES>\n" dataUsingEncoding:NSUTF8StringEncoding]];
//					NSDictionary	*imageSourceImageDict = [imagesInUse objectForKey:imageSourceID];
//					NSEnumerator	*identifierEnumerator = [imageSourceImageDict keyEnumerator];
//					NSString		*identifier = nil;
//					while (identifier = [identifierEnumerator nextObject])
//						[fileHandle writeData:[[NSString stringWithFormat:@"\t\t\t<IMAGE ID=\"%@\" IDENTIFIER=\"%@\">\n", 
//																		 [imageSourceImageDict objectForKey:identifier], identifier]
//													dataUsingEncoding:NSUTF8StringEncoding]];
//					[fileHandle writeData:[@"\t\t</IMAGES>\n" dataUsingEncoding:NSUTF8StringEncoding]];
					
					[fileHandle writeData:[@"\t</IMAGE_SOURCE>\n" dataUsingEncoding:NSUTF8StringEncoding]];
				}
				[fileHandle writeData:[@"</IMAGE_SOURCES>\n\n" dataUsingEncoding:NSUTF8StringEncoding]];
				
					// Write out the tiles
				[fileHandle writeData:[@"<TILES>\n" dataUsingEncoding:NSUTF8StringEncoding]];
				NSMutableString	*buffer = [NSMutableString string];
				NSEnumerator	*tileEnumerator = [tiles objectEnumerator];
				MacOSaiXTile	*tile = nil;
				while (tile = [tileEnumerator nextObject])
				{
					NSAutoreleasePool	*tilePool = [[NSAutoreleasePool alloc] init];
					
					[buffer appendString:@"\t<TILE>\n"];
					
						// First write out the tile's outline
					[buffer appendString:@"\t\t<OUTLINE>\n"];
					int index;
					for (index = 0; index < [[tile outline] elementCount]; index++)
					{
						NSPoint points[3];
						switch ([[tile outline] elementAtIndex:index associatedPoints:points])
						{
							case NSMoveToBezierPathElement:
								[buffer appendString:[NSString stringWithFormat:@"\t\t\t<MOVE_TO X=\"%0.6f\" Y=\"%0.6f\"/>\n", 
																				points[0].x, points[0].y]];
								break;
							case NSLineToBezierPathElement:
								[buffer appendString:[NSString stringWithFormat:@"\t\t\t<LINE_TO X=\"%0.6f\" Y=\"%0.6f\"/>\n", 
																				points[0].x, points[0].y]];
								break;
							case NSCurveToBezierPathElement:
								[buffer appendString:[NSString stringWithFormat:@"\t\t\t<CURVE_TO X=\"%0.6f\" Y=\"%0.6f\" C1X=\"%0.6f\" C1Y=\"%0.6f\" C2X=\"%0.6f\" C2Y=\"%0.6f\"/>\n", 
																				points[2].x, points[2].y, 
																				points[0].x, points[0].y, 
																				points[1].x, points[1].y]];
								break;
							case NSClosePathBezierPathElement:
								[buffer appendString:@"\t\t\t<CLOSE_PATH/>\n"];
								break;
						}
					}
					[buffer appendString:@"\t\t</OUTLINE>\n"];
					
						// Now write out the tile's matches.
					MacOSaiXImageMatch	*uniqueMatch = [tile imageMatch];
					if (uniqueMatch)
					{
						NSString	*sourceID = [self indexAsAlpha:[imageSources indexOfObjectIdenticalTo:[uniqueMatch imageSource]]];
						[buffer appendString:[NSString stringWithFormat:@"\t\t<UNIQUE_MATCH SOURCE=\"%@\" ID=\"%@\" VALUE=\"%f\"/>\n", 
																		  sourceID,
																		  [uniqueMatch imageIdentifier],
																		  [uniqueMatch matchValue]]];
					}
					MacOSaiXImageMatch	*userChosenMatch = [tile userChosenImageMatch];
					if (userChosenMatch)
					{
						NSString	*sourceID = [self indexAsAlpha:[imageSources indexOfObjectIdenticalTo:[userChosenMatch imageSource]]];
						[buffer appendString:[NSString stringWithFormat:@"\t\t<USER_CHOSEN_MATCH SOURCE=\"%@\" ID=\"%@\" VALUE=\"%f\"/>\n", 
																		  sourceID,
																		  [userChosenMatch imageIdentifier],
																		  [userChosenMatch matchValue]]];
					}
//					[fileHandle writeData:[@"\t\t<MATCH_DATA>\n" dataUsingEncoding:NSUTF8StringEncoding]];
//					NSEnumerator	*matchEnumerator = [[tile matches] objectEnumerator];
//					MacOSaiXImageMatch		*match = nil;
//					while (match = [matchEnumerator nextObject])
//					{
//						NSString			*imageSourceID = [self indexAsAlpha:[imageSources indexOfObjectIdenticalTo:[match imageSource]]];
//						NSMutableDictionary	*imageSourceImageDict = [imagesInUse objectForKey:imageSourceID];
//						NSNumber			*imageID = [imageSourceImageDict objectForKey:[match imageIdentifier]];
//						
//						[fileHandle writeData:[[NSString stringWithFormat:@"%@%@\t%d\n", imageSourceID, imageID, [match matchValue] * 100.0]
//													dataUsingEncoding:NSUTF8StringEncoding]];
//					}
//					[fileHandle writeData:[@"\t\t</MATCHDATA>\n" dataUsingEncoding:NSUTF8StringEncoding]];
					
					// TODO: (match == [tile userChosenImageMatch] ? @"USER_CHOSEN" : @"")] 
					
					[buffer appendString:@"\t</TILE>\n"];
					
					if ([buffer length] > 1<<20)
					{
						[fileHandle writeData:[buffer dataUsingEncoding:NSUTF8StringEncoding]];
						[buffer setString:@""];
					}
					
					[tilePool release];
				}
				[fileHandle writeData:[buffer dataUsingEncoding:NSUTF8StringEncoding]];
				[fileHandle writeData:[@"</TILES>\n" dataUsingEncoding:NSUTF8StringEncoding]];
				
				[fileHandle writeData:[@"</MOSAIC>\n\n" dataUsingEncoding:NSUTF8StringEncoding]];
				
				[fileHandle closeFile];
				
				saveSucceeded = YES;
			}
		}
	NS_HANDLER
		NSLog(@"Save failed %@", localException);
	NS_ENDHANDLER
	
		// Dismiss the "Saving..." sheet.
	[[[self windowControllers] objectAtIndex:0] closeProgressPanel];
	
	[self setFileName:savePath];
	[self setFileType:@"MacOSaiX Project"];
	[self updateChangeCount:NSChangeCleared];
	
	NSLog(@"Save completed");
	
	[self setIsSaving:NO];
	
	if (didSaveDelegate && [didSaveDelegate respondsToSelector:didSaveSelector])
	{
		NSLog(@"Calling back to save delegate");
		
			// Now that the save has completed (successfully or not) let the delegate know.
			// The delegate's selector has the signature:
			// - (void)document:(NSDocument *)doc didSave:(BOOL)didSave contextInfo:(void *)contextInfo
		NSMethodSignature	*signature = [[didSaveDelegate class] instanceMethodSignatureForSelector:didSaveSelector];
		NSInvocation		*saveCallback = [NSInvocation invocationWithMethodSignature:signature];
		
		[saveCallback setTarget:didSaveDelegate];
		[saveCallback setSelector:didSaveSelector];
		[saveCallback setArgument:&self atIndex:2];
		[saveCallback setArgument:&saveSucceeded atIndex:3];
		[saveCallback setArgument:&contextInfo atIndex:4];
		[saveCallback invoke];
	}
	
	NSLog(@"Sending save completed notification");
	
		// TODO: include @"User Cancelled" key
	[[NSNotificationCenter defaultCenter] postNotificationName:MacOSaiXDocumentDidSaveNotification 
														object:self 
													  userInfo:nil];

	if (!wasPaused && ![(MacOSaiX *)[NSApp delegate] isQuitting])
		[self resume];

	[pool release];
}


#pragma mark -
#pragma mark Loading


// Loading the saved XML is currently done using the CFXML API so that we can run on Jaguar.
// Once Jaguar support is no longer required this could be cleaned up by switching to the NSXML API.


	// Parser callback prototypes.
void		*createStructure(CFXMLParserRef parser, CFXMLNodeRef node, void *info);
void		addChild(CFXMLParserRef parser, void *parent, void *child, void *info);
void		endStructure(CFXMLParserRef parser, void *xmlType, void *info);
//CFDataRef	resolveExternalEntity(CFXMLParserRef parser, CFXMLExternalID *extID, void *info);
//Boolean		handleError(CFXMLParserRef parser, CFXMLParserStatusCode error, void *info);


- (BOOL)readFromFile:(NSString *)fileName ofType:(NSString *)type
{
	BOOL	success = NO;
	NSData	*xmlData = [NSData dataWithContentsOfFile:[fileName stringByAppendingPathComponent:@"Mosaic.xml"]];
	
	if (xmlData)
	{
			// Set up the parser callbacks and context.
		CFXMLParserCallBacks	callbacks = {0, createStructure, addChild, endStructure, NULL, NULL};	//resolveExternalEntity, handleError};
		CFXMLParserContext		context = {0, self, NULL, NULL, NULL};
		
			// Create the parser with the option to skip whitespace.
		CFXMLParserRef			parser = CFXMLParserCreate(kCFAllocatorDefault, 
														   (CFDataRef)xmlData, 
														   NULL, 
														   kCFXMLParserSkipWhitespace, 
														   kCFXMLNodeCurrentVersion, 
														   &callbacks,
														   &context);

			// Invoke the parser.
		success = CFXMLParserParse(parser);
		
		if (!success)
			NSLog(@"Parsing failed: %@", (NSString *)CFXMLParserCopyErrorDescription(parser));
	}
	
	return success;
}


void *createStructure(CFXMLParserRef parser, CFXMLNodeRef node, void *info)
{
	id					newObject = nil;
	MacOSaiXDocument	*document = (MacOSaiXDocument *)info;
	
    switch (CFXMLNodeGetTypeCode(node))
	{
        case kCFXMLNodeTypeElement:
		{
			NSString			*elementType = (NSString *)CFXMLNodeGetString(node);
			CFXMLElementInfo	*nodeInfo = (CFXMLElementInfo *)CFXMLNodeGetInfoPtr(node);
			
			if ([elementType isEqualToString:@"MOSAIC"])
			{
				newObject = document;
			}
			else if ([elementType isEqualToString:@"ORIGINAL_IMAGE"])
			{
				newObject = [(NSDictionary *)(nodeInfo->attributes) objectForKey:@"PATH"];
			}
			else if ([elementType isEqualToString:@"TILE_SHAPES_SETTINGS"])
			{
				NSString	*className = [(NSDictionary *)(nodeInfo->attributes) objectForKey:@"CLASS"];
				
				newObject = [[NSClassFromString(className) alloc] init];
			}
			else if ([elementType isEqualToString:@"IMAGE_SOURCES"])
			{
				newObject = document;
			}
			else if ([elementType isEqualToString:@"IMAGE_SOURCE"])
			{
				NSString	*className = [(NSDictionary *)(nodeInfo->attributes) objectForKey:@"CLASS"];
				
				newObject = [[NSClassFromString(className) alloc] init];
			}
			else if ([elementType isEqualToString:@"TILES"])
			{
				// could get the count of tiles from an attribute...
				
				newObject = document;
			}
			else if ([elementType isEqualToString:@"TILE"])
			{
				newObject = [[MacOSaiXTile alloc] initWithOutline:nil fromDocument:document];
			}
			else if ([elementType isEqualToString:@"OUTLINE"])
			{
				newObject = [[NSBezierPath bezierPath] retain];
			}
			else if ([elementType isEqualToString:@"MOVE_TO"] || 
					 [elementType isEqualToString:@"LINE_TO"] || 
					 [elementType isEqualToString:@"CURVE_TO"] || 
					 [elementType isEqualToString:@"CLOSE_PATH"])
			{
				newObject = [[NSMutableDictionary dictionaryWithDictionary:(NSDictionary *)nodeInfo->attributes] retain];
				[(NSMutableDictionary *)newObject setObject:elementType forKey:@"Element Type"];
			}
			else if ([elementType isEqualToString:@"UNIQUE_MATCH"])
			{
				int					sourceIndex = [[(NSDictionary *)nodeInfo->attributes objectForKey:@"SOURCE"] intValue];
				NSString			*imageIdentifier = [(NSDictionary *)nodeInfo->attributes objectForKey:@"ID"];
				float				matchValue = [[(NSDictionary *)nodeInfo->attributes objectForKey:@"VALUE"] floatValue];
				
				newObject = [[MacOSaiXImageMatch alloc] initWithMatchValue:matchValue 
														forImageIdentifier:imageIdentifier 
														   fromImageSource:[[document imageSources] objectAtIndex:sourceIndex] 
																   forTile:nil];
			}
			else
			{
				// TODO: hand off unknown elements to image source or tile shapes objects
				newObject = [[NSMutableDictionary dictionaryWithDictionary:(NSDictionary *)nodeInfo->attributes] retain];
				[(NSMutableDictionary *)newObject setObject:elementType forKey:@"Element Type"];
			}
            break;
		}

        default:
			;
	}

    // Return the object that will be passed to the addChild and endStructure callbacks.
    return (void *)newObject;
}


void addChild(CFXMLParserRef parser, void *parent, void *child, void *info)
{
	MacOSaiXDocument	*document = (MacOSaiXDocument *)info;

//	if (parent == nil)
//		parent = document;

	if (parent == document && [(id)child isKindOfClass:[NSString class]])
		[document setOriginalImagePath:(NSString *)child];
	else if (parent == document && [(id)child conformsToProtocol:@protocol(MacOSaiXTileShapes)])
		[document setTileShapes:(id<MacOSaiXTileShapes>)child];
	else if (parent == document && [(id)child conformsToProtocol:@protocol(MacOSaiXImageSource)])
		[document addImageSource:(id<MacOSaiXImageSource>)child];
	else if (parent == document && [(id)child isKindOfClass:[MacOSaiXTile class]])
		[document addTile:(MacOSaiXTile *)child];
	else if ([(id)parent isKindOfClass:[MacOSaiXTile class]] && [(id)child isKindOfClass:[NSBezierPath class]])
		[(MacOSaiXTile *)parent setOutline:(NSBezierPath *)child];
	else if ([(id)parent isKindOfClass:[NSBezierPath class]] && [(id)child isKindOfClass:[NSDictionary class]])
	{
		NSBezierPath	*tileOutline = (NSBezierPath *)parent;
		NSDictionary	*attributes = (NSDictionary *)child;
		NSString		*elementType = [attributes objectForKey:@"Element Type"];
		
		if ([elementType isEqualToString:@"MOVE_TO"])
			[tileOutline moveToPoint:NSMakePoint([[attributes objectForKey:@"X"] floatValue], [[attributes objectForKey:@"Y"] floatValue])];
		else if ([elementType isEqualToString:@"LINE_TO"])
			[tileOutline lineToPoint:NSMakePoint([[attributes objectForKey:@"X"] floatValue], [[attributes objectForKey:@"Y"] floatValue])];
		else if ([elementType isEqualToString:@"CURVE_TO"])
			[tileOutline curveToPoint:NSMakePoint([[attributes objectForKey:@"X"] floatValue], [[attributes objectForKey:@"Y"] floatValue])
						 controlPoint1:NSMakePoint([[attributes objectForKey:@"C1X"] floatValue], [[attributes objectForKey:@"C1Y"] floatValue]) 
						 controlPoint2:NSMakePoint([[attributes objectForKey:@"C2X"] floatValue], [[attributes objectForKey:@"C2Y"] floatValue])];
		else if ([elementType isEqualToString:@"CLOSE_PATH"])
			[tileOutline closePath];
	}
	else if ([(id)parent isKindOfClass:[MacOSaiXTile class]] && [(id)child isKindOfClass:[MacOSaiXImageMatch class]])
	{
		[(MacOSaiXTile *)parent setImageMatch:(MacOSaiXImageMatch *)child];
		[(MacOSaiXImageMatch *)child setTile:(MacOSaiXTile *)parent];
	}
}


void endStructure(CFXMLParserRef parser, void *newObject, void *info)
{
		// Release any objects we created in createStructure() now that they are retained by their parent.
	if ([(id)newObject conformsToProtocol:@protocol(MacOSaiXImageSource)] || 
		[(id)newObject conformsToProtocol:@protocol(MacOSaiXTileShapes)] || 
		[(id)newObject isKindOfClass:[MacOSaiXTile class]] || 
		[(id)newObject isKindOfClass:[NSBezierPath class]] || 
		[(id)newObject isKindOfClass:[NSDictionary class]] || 
		[(id)newObject isKindOfClass:[MacOSaiXImageMatch class]])
		[(id)newObject release];
}


#pragma mark -
#pragma mark Tile management


- (void)calculateTileNeighborhoods
{
		// At a minimum each tile neighbors its direct neighbors.
//	NSEnumerator	*tileEnumerator = [tiles objectEnumerator];
//	MacOSaiXTile	*tile = nil;
//	while (tile = [tileEnumerator nextObject])
//		[tile setNeighboringTiles:[directNeighbors objectForKey:[NSString stringWithFormat:@"%p", tile]]];
//	
//	int	degreeOfSeparation;
//	for (degreeOfSeparation = 1; degreeOfSeparation < neighborhoodSize; degreeOfSeparation++)
//	{
//			// Add the direct neighbors of every tile's neighbor to the tile's neighborhood.
//		NSEnumerator	*tileEnumerator = [tiles objectEnumerator];
//		MacOSaiXTile	*tile = nil;
//		while (tile = [tileEnumerator nextObject])
//		{ 
//			NSAutoreleasePool	*pool2 = [[NSAutoreleasePool alloc] init];
//			NSEnumerator		*neighborEnumerator = [[tile neighboringTiles] objectEnumerator];
//			MacOSaiXTile		*neighbor = nil;
//			
//			while (![self isClosing] && (neighbor = [neighborEnumerator nextObject]))
//				[tile addNeighbors:[directNeighbors objectForKey:[NSString stringWithFormat:@"%p", neighbor]]];
//			
//			[pool2 release];
//		}
//	}
}


- (void)addTile:(MacOSaiXTile *)tile
{
	[tiles addObject:tile];
}


- (void)setTileShapes:(id<MacOSaiXTileShapes>)inTileShapes
{
	[inTileShapes retain];
	[tileShapes autorelease];
	tileShapes = inTileShapes;
	
	NSArray	*tileOutlines = [tileShapes shapes];
	
		// Discard any tiles created from a previous set of outlines.
	if (!tiles)
		tiles = [[NSMutableArray arrayWithCapacity:[tileOutlines count]] retain];
	else
		[tiles removeAllObjects];

		// Create a new tile collection from the outlines.
	NSEnumerator	*tileOutlineEnumerator = [tileOutlines objectEnumerator];
	NSBezierPath	*tileOutline = nil;
    while (tileOutline = [tileOutlineEnumerator nextObject])
		[self addTile:[[[MacOSaiXTile alloc] initWithOutline:tileOutline fromDocument:self] autorelease]];
	
		// Let anyone who cares know that our tile shapes (and thus our tiles array) have changed.
	[[NSNotificationCenter defaultCenter] postNotificationName:MacOSaiXTileShapesDidChangeStateNotification 
														object:self 
													  userInfo:nil];
	
		// Calculate the directly neighboring tiles of each tile.  This is used to calculate
		// each tile's neighborhood when combined with the neighborhood size setting.
//	if (!directNeighbors)
//		directNeighbors = [[NSMutableDictionary dictionary] retain];
//	else
//		[directNeighbors removeAllObjects];
//	NSEnumerator	*tileEnumerator = [tiles objectEnumerator];
//	MacOSaiXTile	*tile = nil;
//    while (tile = [tileEnumerator nextObject])
//	{
//		NSRect	tileBounds = [[tile outline] bounds],
//				zoomedTileBounds = NSZeroRect;
//		
//			// scale the rect up slightly so it overlaps with it's neighbors
//		zoomedTileBounds.size = NSMakeSize(tileBounds.size.width * 1.01, tileBounds.size.height * 1.01);
//		zoomedTileBounds.origin.x += NSMidX(tileBounds) - NSMidX(zoomedTileBounds);
//		zoomedTileBounds.origin.y += NSMidY(tileBounds) - NSMidY(zoomedTileBounds);
//		
//			// Loop through the other tiles and add as neighbors any that intersect.
//			// TO DO: This currently just checks if the bounding boxes of the tiles intersect.
//			//        For non-rectangular tiles this will not be accurate enough.
//		NSMutableArray	*directNeighborArray = [NSMutableArray array];
//		NSEnumerator	*tileEnumerator2 = [tiles objectEnumerator];
//		MacOSaiXTile	*tile2 = nil;
//		while (tile2 = [tileEnumerator2 nextObject])
//			if (tile2 != tile && NSIntersectsRect(zoomedTileBounds, [[tile2 outline] bounds]))
//				[directNeighborArray addObject:tile2];
//		
//		[directNeighbors setObject:directNeighborArray forKey:[NSString stringWithFormat:@"%p", tile]];
//	}
//	
//	[self calculateTileNeighborhoods];
		
	if ([imageSources count] > 0)
		[self resume];
}


- (id<MacOSaiXTileShapes>)tileShapes
{
	return tileShapes;
}


- (int)imageUseCount
{
	return imageUseCount;
}


- (void)setImageUseCount:(int)count
{
	imageUseCount = count;
}


- (int)neighborhoodSize
{
	return neighborhoodSize;
}


- (void)setNeighborhoodSize:(int)size
{
	neighborhoodSize = size;
	
	[[NSUserDefaults standardUserDefaults] setInteger:neighborhoodSize forKey:@"Neighborhood Size"];
	
	// TODO: what if a mosaic is already in the works?  how do we reset?
	
	[self calculateTileNeighborhoods];
	
	mosaicStarted = NO;
}


- (void)extractTileImagesFromOriginalImage
{
    if ([tiles count] == 0 || originalImage == nil)
		return;

	createTilesThreadAlive = YES;
	[[NSNotificationCenter defaultCenter] postNotificationName:MacOSaiXDocumentDidChangeStateNotification object:self];
	
		// Don't usurp the main thread.
	[NSThread setThreadPriority:0.1];
	
    int					index = 0;
    NSAutoreleasePool   *pool = [[NSAutoreleasePool alloc] init];

		// create an offscreen window to draw into (it will have a single, empty view the size of the window)
    NSWindow			*drawWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(-10000, -10000,
																					   [originalImage size].width, 
																					   [originalImage size].height)
																  styleMask:NSBorderlessWindowMask
																    backing:NSBackingStoreBuffered 
																	  defer:NO];
    
	/* Loop through each tile and:
		1. Copy out the rect of the original image that this tile covers.
		2. Calculate an image mask that indicates which part of the copied rect is contained within the tile's outline.
		3. ?
	*/
	NSEnumerator	*tileEnumerator = [tiles objectEnumerator];
	MacOSaiXTile	*tile = nil;
    while (!documentIsClosing && (tile = [tileEnumerator nextObject]))
	{
		index++;
		
			// Lock focus on our 'scratch' window.
		while (![[drawWindow contentView] lockFocusIfCanDraw])
			[NSThread sleepUntilDate:[[NSDate date] addTimeInterval:0.1]];
		
		NS_DURING
				// Determine the bounds of the tile in the original image and in the scratch window.
			NSBezierPath	*tileOutline = [tile outline];
			NSRect  origRect = NSMakeRect([tileOutline bounds].origin.x * [originalImage size].width,
										  [tileOutline bounds].origin.y * [originalImage size].height,
										  [tileOutline bounds].size.width * [originalImage size].width,
										  [tileOutline bounds].size.height * [originalImage size].height),
					destRect = (origRect.size.width > origRect.size.height) ?
								NSMakeRect(0, 0, TILE_BITMAP_SIZE, TILE_BITMAP_SIZE * origRect.size.height / origRect.size.width) : 
								NSMakeRect(0, 0, TILE_BITMAP_SIZE * origRect.size.width / origRect.size.height, TILE_BITMAP_SIZE);
			
				// Start with a black image to overwrite any previous scratch contents.
			[[NSColor blackColor] set];
			[[NSBezierPath bezierPathWithRect:destRect] fill];
			
				// Copy out the portion of the original image contained by the tile's outline.
			[originalImage drawInRect:destRect fromRect:origRect operation:NSCompositeCopy fraction:1.0];
			NSBitmapImageRep	*tileRep = [[[NSBitmapImageRep alloc] initWithFocusedViewRect:destRect] autorelease];
			if (tileRep == nil) NSLog(@"Could not create tile bitmap");
			#if 0
				[[tileRep TIFFRepresentationUsingCompression:NSTIFFCompressionLZW factor:1.0] 
					writeToFile:[NSString stringWithFormat:@"/tmp/MacOSaiX/%4d.tiff", index] atomically:NO];
			#endif
		
				// Calculate a mask image using the tile's outline that is the same size as the image
				// extracted from the original.  The mask will be white for pixels that are inside the 
				// tile and black outside.
				// (This would work better if we could just replace the previous rep's alpha channel
				//  but I haven't figured out an easy way to do that yet.)
			[[NSGraphicsContext currentContext] saveGraphicsState];	// so we can undo the clip
					// Start with a black background.
				[[NSColor blackColor] set];
				[[NSBezierPath bezierPathWithRect:destRect] fill];
				
					// Fill the tile's outline with white.
				NSAffineTransform  *transform = [NSAffineTransform transform];
				[transform scaleXBy:destRect.size.width / [tileOutline bounds].size.width
								yBy:destRect.size.height / [tileOutline bounds].size.height];
				[transform translateXBy:[tileOutline bounds].origin.x * -1
									yBy:[tileOutline bounds].origin.y * -1];
				[[NSColor whiteColor] set];
				[[transform transformBezierPath:tileOutline] fill];
				
					// Copy out the mask image and store it in the tile.
					// TO DO: RGB is wasting space, should be grayscale.
				NSBitmapImageRep	*maskRep = [[[NSBitmapImageRep alloc] initWithFocusedViewRect:destRect] autorelease];
				[tile setBitmapRep:tileRep withMask:maskRep];
				#if 0
					[[maskRep TIFFRepresentationUsingCompression:NSTIFFCompressionLZW factor:1.0] 
						writeToFile:[NSString stringWithFormat:@"/tmp/MacOSaiX/%4dMask.tiff", index] atomically:NO];
				#endif
			[[NSGraphicsContext currentContext] restoreGraphicsState];
		NS_HANDLER
			NSLog(@"Exception raised while extracting tile images: %@", [localException name]);
		NS_ENDHANDLER
		
			// Release our lock on the GUI in case the main thread needs it.
		[[drawWindow contentView] unlockFocus];
		
		tileCreationPercentComplete = (int)(index * 100.0 / [tiles count]);
		[[NSNotificationCenter defaultCenter] postNotificationName:MacOSaiXDocumentDidChangeStateNotification object:self];
	}
	
    [drawWindow close];
    
		// Start up the mosaic
	[self resume];

    [pool release];
    
    createTilesThreadAlive = NO;
	
	[[NSNotificationCenter defaultCenter] postNotificationName:MacOSaiXDocumentDidChangeStateNotification object:self];
}


- (BOOL)isExtractingTileImagesFromOriginal
{
	return createTilesThreadAlive;
}


- (float)tileCreationPercentComplete
{
	return tileCreationPercentComplete;
}


- (NSArray *)tiles
{
	return tiles;
}


#pragma mark -
#pragma mark Image source enumeration


- (void)spawnImageSourceThreads
{
	NSEnumerator			*imageSourceEnumerator = [imageSources objectEnumerator];
	id<MacOSaiXImageSource>	imageSource;
	
	while (imageSource = [imageSourceEnumerator nextObject])
		[NSApplication detachDrawingThread:@selector(enumerateImageSourceInNewThread:) toTarget:self withObject:imageSource];
}


- (void)enumerateImageSourceInNewThread:(id<MacOSaiXImageSource>)imageSource
{
	[enumerationThreadCountLock lock];
		enumerationThreadCount++;
	[enumerationThreadCountLock unlock];
	[[NSNotificationCenter defaultCenter] postNotificationName:MacOSaiXDocumentDidChangeStateNotification object:self];
	
		// Don't usurp the main thread.
	[NSThread setThreadPriority:0.1];
	
		// Check if the source has any images left.
	NSAutoreleasePool	*pool = [[NSAutoreleasePool alloc] init];
	BOOL				sourceHasMoreImages = [imageSource hasMoreImages];
	[pool release];
	
	while (!documentIsClosing && sourceHasMoreImages)
	{
		NSAutoreleasePool	*pool = [[NSAutoreleasePool alloc] init];
		
		[self lockWhilePaused];
		
			// Get the next image from the source (and identifier if there is one)
		NSString	*imageIdentifier = nil;
		NSImage		*image = [imageSource nextImageAndIdentifier:&imageIdentifier];
		
			// Set the caching behavior of the image.  We'll be adding bitmap representations of various
			// sizes to the image so it doesn't need to do any of its own caching.
//		[image setCacheMode:NSImageCacheNever];
		[image setCachedSeparately:YES];
		
		BOOL	imageIsValid = NO;
		
		NS_DURING
			imageIsValid = [image isValid];
		NS_HANDLER
			NSLog(@"Exception raised while checking image validity (%@)", localException);
		NS_ENDHANDLER
			
		if (image && imageIsValid)
		{
				// Ignore whatever DPI was set for the image.  We just care about the bitmap.
			NSImageRep	*originalRep = [[image representations] objectAtIndex:0];
			[originalRep setSize:NSMakeSize([originalRep pixelsWide], [originalRep pixelsHigh])];
			[image setSize:NSMakeSize([originalRep pixelsWide], [originalRep pixelsHigh])];
			
			if ([image size].width > 16 && [image size].height > 16)
			{
				[imageQueueLock lock];	// this will be locked if the queue is full
					while (!documentIsClosing && [imageQueue count] > MAXIMAGEURLS)
					{
						[imageQueueLock unlock];
						[imageQueueLock lock];
					}
					
					// TODO: are we losing an image if documentIsClosing?
					
					[image setCachedSeparately:YES];
//					[image setCacheMode:NSImageCacheNever];
					
					[imageQueue addObject:[NSDictionary dictionaryWithObjectsAndKeys:
												image, @"Image",
												imageSource, @"Image Source", 
												imageIdentifier, @"Image Identifier", // last since it could be nil
												nil]];
					
					[enumerationCountsLock lock];
						NSString		*key = [NSString stringWithFormat:@"%p", imageSource];
						unsigned long	currentCount = [[enumerationCounts objectForKey:key] unsignedLongValue];
						[enumerationCounts setObject:[NSNumber numberWithUnsignedLong:currentCount + 1] forKey:key];
					[enumerationCountsLock unlock];
				[imageQueueLock unlock];

				if (!documentIsClosing && !calculateImageMatchesThreadAlive)
					[NSApplication detachDrawingThread:@selector(calculateImageMatches:) toTarget:self withObject:nil];
				
				[[NSNotificationCenter defaultCenter] postNotificationName:MacOSaiXDocumentDidChangeStateNotification object:self];
			}
		}
		sourceHasMoreImages = [imageSource hasMoreImages];
		
		[pool release];
	}
	
	[enumerationThreadCountLock lock];
		enumerationThreadCount--;
	[enumerationThreadCountLock unlock];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:MacOSaiXDocumentDidChangeStateNotification object:self];
}


- (BOOL)isEnumeratingImageSources
{
	return (enumerationThreadCount > 0);
}


- (unsigned long)countOfImagesFromSource:(id<MacOSaiXImageSource>)imageSource
{
	unsigned long	enumerationCount = 0;
	
	[enumerationCountsLock lock];
		enumerationCount = [[enumerationCounts objectForKey:[NSString stringWithFormat:@"%p", imageSource]] unsignedLongValue];
	[enumerationCountsLock unlock];
	
	return enumerationCount;
}


- (unsigned long)imagesMatched
{
	unsigned long	totalCount = 0;
	
	[enumerationCountsLock lock];
		NSEnumerator	*sourceEnumerator = [enumerationCounts keyEnumerator];
		NSString		*key = nil;
		while (key = [sourceEnumerator nextObject])
			totalCount += [[enumerationCounts objectForKey:key] unsignedLongValue];
	[enumerationCountsLock unlock];
	
	return totalCount;
}


#pragma mark -
#pragma mark Image matching


- (void)calculateImageMatches:(id)dummy
{
		// This method is called in a new thread whenever a non-empty image queue is discovered.
		// It pulls images from the queue and matches them against each tile.  Once the queue
		// is empty the method will end and the thread is terminated.
    NSAutoreleasePool	*pool = [[NSAutoreleasePool alloc] init];

        // Make sure only one copy of this thread runs at any time.
	[calculateImageMatchesThreadLock lock];
		if (calculateImageMatchesThreadAlive)
		{
                // Another copy is running, just exit.
			[calculateImageMatchesThreadLock unlock];
			[pool release];
			return;
		}
		calculateImageMatchesThreadAlive = YES;
	[calculateImageMatchesThreadLock unlock];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:MacOSaiXDocumentDidChangeStateNotification object:self];
	
//	NSLog(@"Calculating image matches\n");
	
		// Don't usurp the main thread.
	[NSThread setThreadPriority:0.1];

	[imageQueueLock lock];
    while (!documentIsClosing && [imageQueue count] > 0)
	{
			// As long as the image source threads are feeding images into the queue this loop
			// will continue running so create a pool just for this pass through the loop.
		NSAutoreleasePool	*pool2 = [[NSAutoreleasePool alloc] init];
		BOOL				queueLocked = NO;
		
			// pull the next image from the queue
		NSDictionary		*nextImageDict = [[[imageQueue objectAtIndex:0] retain] autorelease];
		[imageQueue removeObjectAtIndex:0];
		
			// let the image source threads add more images if the queue is not full
		if ([imageQueue count] < MAXIMAGEURLS)
			[imageQueueLock unlock];
		else
			queueLocked = YES;
		
		NSImage					*pixletImage = [nextImageDict objectForKey:@"Image"];
		id<MacOSaiXImageSource>	pixletImageSource = [nextImageDict objectForKey:@"Image Source"];
		NSString				*pixletImageIdentifier = [nextImageDict objectForKey:@"Image Identifier"];
		
//		NSLog(@"Matching %@ from %@", pixletImageIdentifier, pixletImageSource);
		
		if (pixletImage)
		{
				// Add this image to the cache.  If the identifier is nil or zero-length then 
				// a new identifier will be returned.
			pixletImageIdentifier = [[MacOSaiXImageCache sharedImageCache] cacheImage:pixletImage withIdentifier:pixletImageIdentifier fromSource:pixletImageSource];
		}
		
			// Find the tiles that match this image better than their current image.
		NSString		*pixletKey = [NSString stringWithFormat:@"%p %@", pixletImageSource, pixletImageIdentifier];
		NSMutableArray	*betterMatches = [betterMatchesCache objectForKey:pixletKey];
		if (betterMatches)
		{
				// Remove any tiles from the list that have gotten a better match since the list was cached.
				// Also remove any tiles that have the exact same match value but for a different image.  This 
				// avoids infinite loop conditions if you have multiple image files containing the exact same image.
			NSEnumerator		*betterMatchEnumerator = [[NSArray arrayWithArray:betterMatches] objectEnumerator];
			MacOSaiXImageMatch	*betterMatch = nil;
			while ((betterMatch = [betterMatchEnumerator nextObject]) && !documentIsClosing)
			{
				MacOSaiXImageMatch	*currentMatch = [[betterMatch tile] imageMatch];
				if (currentMatch && ([currentMatch matchValue] < [betterMatch matchValue] || 
									 ([currentMatch matchValue] == [betterMatch matchValue] && 
										([currentMatch imageSource] != [betterMatch imageSource] || 
										 [currentMatch imageIdentifier] != [betterMatch imageIdentifier]))))
					[betterMatches removeObjectIdenticalTo:betterMatch];
			}
		}
		else
		{
				// Loop through all of the tiles and calculate how well this image matches.
			betterMatches = [NSMutableArray array];
			NSEnumerator	*tileEnumerator = [tiles objectEnumerator];
			MacOSaiXTile	*tile = nil;
			while ((tile = [tileEnumerator nextObject]) && !documentIsClosing)
			{
				NSAutoreleasePool	*pool3 = [[NSAutoreleasePool alloc] init];
				
					// Get a rep for the image scaled to the tile's bitmap size.
				NSBitmapImageRep	*imageRep = [[MacOSaiXImageCache sharedImageCache] imageRepAtSize:[[tile bitmapRep] size] 
																					    forIdentifier:pixletImageIdentifier 
																						   fromSource:pixletImageSource];
		
				if (imageRep)
				{
						// Calculate how well this image matches this tile.
					float	matchValue = [tile matchValueForImageRep:imageRep
													  withIdentifier:pixletImageIdentifier
													 fromImageSource:pixletImageSource];
					
						// If the tile does not already have a match or 
						//    this image matches better than the tile's current best or
						//    this image is the same as the tile's current best
						// then add it to the list of tile's that might get this image.
					if (![tile imageMatch] || 
						matchValue < [[tile imageMatch] matchValue] ||
						([[tile imageMatch] imageSource] == pixletImageSource && 
						 [[[tile imageMatch] imageIdentifier] isEqualToString:pixletImageIdentifier]))
						[betterMatches addObject:[[[MacOSaiXImageMatch alloc] initWithMatchValue:matchValue 
																			  forImageIdentifier:pixletImageIdentifier 
																				 fromImageSource:pixletImageSource
																						 forTile:tile] autorelease]];
				}
				
				[pool3 release];
			}
			
			[betterMatches sortUsingSelector:@selector(compare:)];
			[betterMatchesCache setObject:betterMatches forKey:pixletKey];
		}
		
		if ([betterMatches count] == 0)
		{
//			NSLog(@"%@ from %@ is not needed", pixletImageIdentifier, pixletImageSource);
			[betterMatchesCache removeObjectForKey:pixletKey];
			
			// TBD: Is this the right place to purge images from the disk cache?
		}
		else
		{
				// Figure out which tiles should be set to use the image based on the user's settings.
				// Just allow a fixed number of uses of each image for now.  No neighborhood size yet.
			int	i, useCount = [self imageUseCount];
			if (useCount == 0 || [betterMatches count] < useCount)
				useCount = [betterMatches count];
			for (i = 0; i < useCount; i++)
			{
				MacOSaiXImageMatch	*betterMatch = [betterMatches objectAtIndex:i];
				MacOSaiXTile		*tile = [betterMatch tile];
				
					// Add the tile's current image back to the queue so it can potentially get re-used by other tiles.
				MacOSaiXImageMatch	*previousMatch = [tile imageMatch];
				if (previousMatch && ([previousMatch imageSource] != pixletImageSource || 
					![[previousMatch imageIdentifier] isEqualToString:pixletImageIdentifier]) &&
					[self imageUseCount] > 0)
				{
					if (!queueLocked)
					{
						[imageQueueLock lock];
						queueLocked = YES;
					}
					
					NSDictionary	*newQueueEntry = [NSDictionary dictionaryWithObjectsAndKeys:
														[previousMatch imageSource], @"Image Source", 
														[previousMatch imageIdentifier], @"Image Identifier",
														nil];
					if (![imageQueue containsObject:newQueueEntry])
					{
//						NSLog(@"Rechecking %@", [previousMatch imageIdentifier]);
						[imageQueue addObject:newQueueEntry];
					}
				}
				
				[tile setImageMatch:betterMatch];
			}
			[self updateChangeCount:NSChangeDone];
		}
		
		if (pixletImage)
			imagesMatched++;
		
		if (!queueLocked)
			[imageQueueLock lock];

		[pool2 release];
	}
	[imageQueueLock unlock];

	[calculateImageMatchesThreadLock lock];
		calculateImageMatchesThreadAlive = NO;
	[calculateImageMatchesThreadLock unlock];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:MacOSaiXDocumentDidChangeStateNotification object:self];
	
		// clean up and shutdown this thread
    [pool release];
}

- (BOOL)isCalculatingImageMatches
{
	return calculateImageMatchesThreadAlive;
}


#pragma mark -
#pragma mark Images source methods


- (NSArray *)imageSources
{
	return [NSArray arrayWithArray:imageSources];
}


- (void)addImageSource:(id<MacOSaiXImageSource>)imageSource
{
	[imageSources addObject:imageSource];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:MacOSaiXDocumentDidChangeStateNotification object:self];
	
	[NSApplication detachDrawingThread:@selector(enumerateImageSourceInNewThread:) 
							  toTarget:self 
							withObject:imageSource];
}


- (void)removeImageSource:(id<MacOSaiXImageSource>)imageSource
{
	[imageSources removeObject:imageSource];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:MacOSaiXDocumentDidChangeStateNotification object:self];
}


#pragma mark -


- (void)canCloseDocumentWithDelegate:(id)delegate 
				 shouldCloseSelector:(SEL)shouldCloseSelector
						 contextInfo:(void *)contextInfo
{
	NSLog(@"\"Can close document\" called");
	
		// pause threads so document dirty state doesn't change
    if (!paused)
		[self pause];
    
	if ([self isDocumentEdited])
	{
			// Present a sheet that allows the user to save, cancel or not save.
			// TODO: get the localized versions of these strings
		NSString		*title = [NSString stringWithFormat:@"Do you want to save the changes you made in document \"%@\"?",
															[[self fileName] lastPathComponent]], 
						*saveString = @"Save",
						*dontSaveString = @"Don't Save", 
						*cancelString = @"Cancel", 
						*message = @"Your changes will be lost if you don't save them.";
		NSDictionary	*metaContextInfo = [[NSDictionary dictionaryWithObjectsAndKeys:
												delegate, @"Should Close Delegate", 
												NSStringFromSelector(shouldCloseSelector), @"Should Close Selector", 
												[NSString stringWithFormat:@"%p", contextInfo], @"Context Info",
												nil] retain];
		
		NSBeginAlertSheet(title, saveString, dontSaveString, cancelString, 
						  [[[self windowControllers] objectAtIndex:0] window],
						  self, nil, @selector(shouldCloseSheetDidDismiss:returnCode:contextInfo:), metaContextInfo, 
						  message);
	}
	else
		[super canCloseDocumentWithDelegate:delegate shouldCloseSelector:shouldCloseSelector 
					contextInfo:contextInfo];
}


- (void)shouldCloseSheetDidDismiss:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)metaContextInfo
{
	BOOL	shouldClose = NO;
	
	switch (returnCode)
	{
		case NSAlertDefaultReturn:
				// The user chose to save.  When the save is complete it will call back to our
				// method which will then call back to the close initiator.
			[self saveDocumentWithDelegate:self 
						   didSaveSelector:@selector(closeAfterDocument:didSave:contextInfo:) 
							   contextInfo:metaContextInfo];
			break;

			// The user chose to cancel or not to save.  Immediately call back to the close initiator,
			// returning NO if they cancelled or YES if they chose not to save.
		case NSAlertAlternateReturn:
			shouldClose = YES;
		case NSAlertOtherReturn:
		{
			id		shouldCloseDelegate = [(NSDictionary *)metaContextInfo objectForKey:@"Should Close Delegate"];
			SEL		shouldCloseSelector = NSSelectorFromString([(NSDictionary *)metaContextInfo objectForKey:@"Should Close Selector"]);
			void	*contextInfo = nil;
			if ([(NSDictionary *)metaContextInfo objectForKey:@"Context Info"])
				sscanf([[(NSDictionary *)metaContextInfo objectForKey:@"Context Info"] UTF8String], "%p", &contextInfo);
			
			if (shouldCloseDelegate && [shouldCloseDelegate respondsToSelector:shouldCloseSelector])
			{
					// Now that the save has completed (successfully or not) let the delegate know.
					// The delegate's selector has the signature:
					// - (void)document:(NSDocument *)doc shouldClose:(BOOL)didSave contextInfo:(void *)contextInfo
				NSMethodSignature	*signature = [[shouldCloseDelegate class] instanceMethodSignatureForSelector:shouldCloseSelector];
				NSInvocation		*shouldCloseCallback = [NSInvocation invocationWithMethodSignature:signature];
				
				[shouldCloseCallback setTarget:shouldCloseDelegate];
				[shouldCloseCallback setSelector:shouldCloseSelector];
				[shouldCloseCallback setArgument:&self atIndex:2];
				[shouldCloseCallback setArgument:&shouldClose atIndex:3];
				[shouldCloseCallback setArgument:&contextInfo atIndex:4];
				[shouldCloseCallback invoke];
			}
			
			[(id)metaContextInfo release];
			break;
		}
	}
}


- (void)closeAfterDocument:(NSDocument *)doc didSave:(BOOL)didSave contextInfo:(void *)metaContextInfo
{
		// The save has completed so call back to the close initiator.
	id		shouldCloseDelegate = [(NSDictionary *)metaContextInfo objectForKey:@"Should Close Delegate"];
	SEL		shouldCloseSelector = NSSelectorFromString([(NSDictionary *)metaContextInfo objectForKey:@"Should Close Selector"]);
	void	*contextInfo = nil;
	if ([(NSDictionary *)metaContextInfo objectForKey:@"Context Info"])
		sscanf([[(NSDictionary *)metaContextInfo objectForKey:@"Context Info"] UTF8String], "%p", &contextInfo);
	
	if (shouldCloseDelegate && [shouldCloseDelegate respondsToSelector:shouldCloseSelector])
	{
			// Now that the save has completed (successfully or not) let the delegate know.
			// The delegate's selector has the signature:
			// - (void)document:(NSDocument *)doc shouldClose:(BOOL)didSave contextInfo:(void *)contextInfo
		NSMethodSignature	*signature = [[shouldCloseDelegate class] instanceMethodSignatureForSelector:shouldCloseSelector];
		NSInvocation		*shouldCloseCallback = [NSInvocation invocationWithMethodSignature:signature];
		
		[shouldCloseCallback setTarget:shouldCloseDelegate];
		[shouldCloseCallback setSelector:shouldCloseSelector];
		[shouldCloseCallback setArgument:&self atIndex:2];
		[shouldCloseCallback setArgument:&didSave atIndex:3];
		[shouldCloseCallback setArgument:&contextInfo atIndex:4];
		[shouldCloseCallback invoke];
	}
	
	[(id)metaContextInfo release];
}


- (BOOL)isClosing
{
	return documentIsClosing;
}


- (void)close
{
	NSLog(@"Closing document");
	
	if (documentIsClosing)
		return;	// make sure to do the steps below only once (not sure why this method sometimes gets called twice...)
	
		// Let the helper threads know we are closing and resume so that they can exit.
	documentIsClosing = YES;
	[self resume];
	
		// wait for the threads to shut down
    while ([self isExtractingTileImagesFromOriginal] || [self isEnumeratingImageSources] || [self isCalculatingImageMatches])
		[NSThread sleepUntilDate:[[NSDate date] addTimeInterval:1.0]];
		
		// Give the image sources a chance to clean up before we close shop
	[imageSources release];
	imageSources = nil;
	
    [super close];
}


#pragma mark -


- (void)dealloc
{
	NSLog(@"Dealloc'ing document");
	
    [originalImagePath release];
    [originalImage release];
	[pauseLock release];
    [imageQueueLock release];
	[enumerationThreadCountLock release];
	[enumerationCountsLock release];
	[enumerationCounts release];
	[betterMatchesCache release];
	[calculateImageMatchesThreadLock release];
    [tiles release];
    [tileShapes release];
    [imageQueue release];
    [lastSaved release];
    [tileImages release];
    [tileImagesLock release];
	[directNeighbors release];
	
    [super dealloc];
}

@end
