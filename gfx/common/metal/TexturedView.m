//
// Created by Stuart Carnie on 6/16/18.
//

#import "TexturedView.h"
#import "RendererCommon.h"
#import "View.h"
#import "Filter.h"

@implementation TexturedView
{
   Context *_context;
   id<MTLTexture> _texture; // optimal render texture
   Vertex _v[4];
   CGSize _size; // size of view in pixels
   CGRect _frame;
   NSUInteger _bpp;
   
   id<MTLBuffer> _pixels;   // frame buffer in _srcFmt
   bool _pixelsDirty;
}

- (instancetype)initWithDescriptor:(ViewDescriptor *)d context:(Context *)c
{
   self = [super init];
   if (self)
   {
      _format = d.format;
      _bpp = RPixelFormatToBPP(_format);
      _filter = d.filter;
      _context = c;
      _visible = YES;
      if (_format == RPixelFormatBGRA8Unorm || _format == RPixelFormatBGRX8Unorm)
      {
         _drawState = ViewDrawStateEncoder;
      }
      else
      {
         _drawState = ViewDrawStateAll;
      }
      self.size = d.size;
      self.frame = CGRectMake(0, 0, 1, 1);
   }
   return self;
}

- (void)setSize:(CGSize)size
{
   if (CGSizeEqualToSize(_size, size))
   {
      return;
   }
   
   _size = size;
   
   // create new texture
   {
      MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                    width:(NSUInteger)size.width
                                                                                   height:(NSUInteger)size.height
                                                                                mipmapped:NO];
      td.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
      _texture = [_context.device newTextureWithDescriptor:td];
   }
   
   if (_format != RPixelFormatBGRA8Unorm && _format != RPixelFormatBGRX8Unorm)
   {
      _pixels = [_context.device newBufferWithLength:(NSUInteger)(size.width * size.height * 2)
                                             options:MTLResourceStorageModeManaged];
   }
}

- (CGSize)size
{
   return _size;
}

- (void)setFrame:(CGRect)frame
{
   if (CGRectEqualToRect(_frame, frame))
   {
      return;
   }
   
   _frame = frame;
   
   // update vertices
   CGPoint o = frame.origin;
   CGSize s = frame.size;
   
   float l = o.x;
   float t = o.y;
   float r = o.x + s.width;
   float b = o.y + s.height;
   
   Vertex v[4] = {
      {{l, b, 0}, {0, 1}},
      {{r, b, 0}, {1, 1}},
      {{l, t, 0}, {0, 0}},
      {{r, t, 0}, {1, 0}},
   };
   memcpy(_v, v, sizeof(_v));
}

- (CGRect)frame
{
   return _frame;
}

- (void)_convertFormat
{
   if (_format == RPixelFormatBGRA8Unorm || _format == RPixelFormatBGRX8Unorm)
      return;
   
   if (!_pixelsDirty)
      return;
   
   [_context convertFormat:_format from:_pixels to:_texture];
   _pixelsDirty = NO;
}

- (void)drawWithContext:(Context *)ctx
{
   [self _convertFormat];
}

- (void)drawWithEncoder:(id<MTLRenderCommandEncoder>)rce
{
   [rce setVertexBytes:&_v length:sizeof(_v) atIndex:BufferIndexPositions];
   [rce setFragmentTexture:_texture atIndex:TextureIndexColor];
   [rce drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

- (void)updateFrame:(void const *)src pitch:(NSUInteger)pitch
{
   if (_format == RPixelFormatBGRA8Unorm || _format == RPixelFormatBGRX8Unorm)
   {
      [_texture replaceRegion:MTLRegionMake2D(0, 0, (NSUInteger)_size.width, (NSUInteger)_size.height)
                  mipmapLevel:0 withBytes:src
                  bytesPerRow:(NSUInteger)(4 * pitch)];
   }
   else
   {
      void *dst = _pixels.contents;
      size_t len = (size_t)(_bpp * _size.width);
      assert(len <= pitch); // the length can't be larger?
      
      if (len < pitch)
      {
         for (int i = 0; i < _size.height; i++)
         {
            memcpy(dst, src, len);
            dst += len;
            src += pitch;
         }
      }
      else
      {
         memcpy(dst, src, _pixels.length);
      }
      
      [_pixels didModifyRange:NSMakeRange(0, _pixels.length)];
      _pixelsDirty = YES;
   }
}

@end
