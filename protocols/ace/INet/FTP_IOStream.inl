// -*- C++ -*-
//
// $Id: FTP_IOStream.inl 90891 2010-06-28 09:55:39Z mcorino $

ACE_BEGIN_VERSIONED_NAMESPACE_DECL

namespace ACE
{
  namespace FTP
  {

    ACE_INLINE
    StreamBuffer* IOS::rdbuf ()
      {
        return &this->streambuf_;
      }

    ACE_INLINE
    void OStream::set_interceptor (StreamBuffer::interceptor_type& interceptor)
      {
        this->rdbuf ()->set_interceptor (interceptor);
      }

    ACE_INLINE
    void IStream::set_interceptor (StreamBuffer::interceptor_type& interceptor)
      {
        this->rdbuf ()->set_interceptor (interceptor);
      }

  }
}

ACE_END_VERSIONED_NAMESPACE_DECL
