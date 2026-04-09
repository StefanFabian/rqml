/*
 * Copyright (C) 2025  Stefan Fabian
 *
 * This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#include "depth_image_processor.hpp"
#include <QDebug>
#include <QImage>
#include <QVideoFrame>

// Define restrict macro for different compilers to mark pointer arguments as non-aliasing
// and enable further optimization.
#if defined( __GNUC__ ) || defined( __clang__ )
  #define RESTRICT __restrict__
#elif defined( _MSC_VER )
  #define RESTRICT __restrict
#else
  #define RESTRICT
#endif

DepthImageProcessor::DepthImageProcessor( QObject *parent ) : QObject( parent )
{
  input_sink_ = new QVideoSink( this );
  connect( input_sink_, &QVideoSink::videoFrameChanged, this, &DepthImageProcessor::processFrame );
}

QVideoSink *DepthImageProcessor::videoSink() const { return input_sink_; }

QVideoSink *DepthImageProcessor::outputVideoSink() const { return output_sink_; }

void DepthImageProcessor::setOutputVideoSink( QVideoSink *sink )
{
  if ( output_sink_ == sink )
    return;
  output_sink_ = sink;
  emit outputVideoSinkChanged();
}

double DepthImageProcessor::maxDepth() const { return max_depth_; }

void DepthImageProcessor::setMaxDepth( double depth )
{
  if ( qFuzzyCompare( max_depth_, depth ) )
    return;
  max_depth_ = depth;
  processFrame();
  emit maxDepthChanged();
}

void DepthImageProcessor::grabFrame()
{
  if ( !output_sink_ )
    return;
  grabbed_frame_ = output_sink_->videoFrame();
}

void DepthImageProcessor::clearGrabbedFrame() { grabbed_frame_ = QVideoFrame(); }

bool DepthImageProcessor::saveGrabbedFrame( const QString &path )
{
  if ( !grabbed_frame_.isValid() ) {
    qWarning() << "No frame grabbed to save.";
    return false;
  }

  QImage image = grabbed_frame_.toImage();
  if ( image.isNull() ) {
    qWarning() << "Failed to convert grabbed frame to image.";
    return false;
  }

  // For Y16 format, convert to ARGB32 and set pixels with zero depth to transparent
  if ( input_sink_->videoFrame().pixelFormat() == QVideoFrameFormat::Format_Y16 ) {
    image = image.convertToFormat( QImage::Format_ARGB32 );
    if ( grabbed_frame_.map( QVideoFrame::ReadOnly ) ) {
      const int width = grabbed_frame_.width();
      const int height = grabbed_frame_.height();
      const int stride = grabbed_frame_.bytesPerLine( 0 );
      const uchar *data = grabbed_frame_.bits( 0 );
      for ( int y = 0; y < height; ++y ) {
        auto *RESTRICT image_line = reinterpret_cast<QRgb *>( image.scanLine( y ) );
        const uchar *RESTRICT frame_line = data + y * stride;
        for ( int x = 0; x < width; ++x ) {
          image_line[x] = frame_line[x] == 0 ? 0 : image_line[x];
        }
      }
      grabbed_frame_.unmap();
    } else {
      qWarning() << "Failed to map grabbed frame for transparency processing. Saving without "
                    "transparency.";
    }
  }

  qInfo() << "Saving grabbed frame to" << path;
  if ( !image.save( path ) ) {
    qWarning() << "Failed to save image to" << path;
    return false;
  }
  return true;
}

void DepthImageProcessor::processFrame()
{
  if ( !output_sink_ )
    return;

  QVideoFrame frame = input_sink_->videoFrame();
  if ( !frame.isValid() || frame.pixelFormat() != QVideoFrameFormat::Format_Y16 ||
       max_depth_ <= 0.001 ) {
    output_sink_->setVideoFrame( frame );
    return;
  }

  if ( !frame.map( QVideoFrame::ReadOnly ) ) {
    output_sink_->setVideoFrame( frame );
    return;
  }

  // Scale Y16 depth data to Y8 grayscale based on maxDepth property
  QVideoFrameFormat out_format( frame.size(), QVideoFrameFormat::Format_Y8 );
  QVideoFrame out_frame( out_format );

  if ( !out_frame.map( QVideoFrame::WriteOnly ) ) {
    frame.unmap();
    output_sink_->setVideoFrame( frame );
    return;
  }

  const int width = frame.width();
  const int height = frame.height();
  const int in_stride = frame.bytesPerLine( 0 );
  const int out_stride = out_frame.bytesPerLine( 0 );
  const uchar *RESTRICT in_data = frame.bits( 0 );
  uchar *RESTRICT out_data = out_frame.bits( 0 );

  // maxDepth is in meters. Y16 is in mm. 0 is no depth info, so scale to [1, 255]
  double scale = 254.0 / ( max_depth_ * 1000.0 );

  for ( int y = 0; y < height; ++y ) {
    const quint16 *RESTRICT in_row = reinterpret_cast<const quint16 *>( in_data + y * in_stride );
    uchar *RESTRICT out_row = out_data + y * out_stride;
    for ( int x = 0; x < width; ++x ) {
      const double val = in_row[x] == 0 ? 0 : 1 + in_row[x] * scale;
      out_row[x] = val > 255 ? 255 : static_cast<uchar>( val );
    }
  }

  frame.unmap();
  out_frame.unmap();

  output_sink_->setVideoFrame( out_frame );
}
