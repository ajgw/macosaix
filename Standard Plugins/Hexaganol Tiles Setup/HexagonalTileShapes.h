//
//  HexagonalTileShapes.h
//  MacOSaiX
//
//  Created by Frank Midgley on Sat Mar 12 2005.
//  Copyright (c) 2003-2005 Frank M. Midgley. All rights reserved.
//

#import "MacOSaiXTileShapes.h"


@interface MacOSaiXHexagonalTileShape : NSObject <MacOSaiXTileShape>
{
	NSBezierPath	*outline;
	float			imageOrientation;
}

+ (MacOSaiXHexagonalTileShape *)tileShapeWithOutline:(NSBezierPath *)inOutline imageOrientation:(float)angle;
- (id)initWithOutline:(NSBezierPath *)outline imageOrientation:(float)angle;

@end


@interface MacOSaiXHexagonalTileShapes : NSObject <MacOSaiXTileShapes>
{
	unsigned int	tilesAcross, 
					tilesDown;
}

- (void)setTilesAcross:(unsigned int)count;
- (unsigned int)tilesAcross;

- (void)setTilesDown:(unsigned int)count;
- (unsigned int)tilesDown;

@end
