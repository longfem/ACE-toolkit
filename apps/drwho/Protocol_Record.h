/* -*- C++ -*- */

//=============================================================================
/**
 *  @file    Protocol_Record.h
 *
 *  $Id: Protocol_Record.h 93651 2011-03-28 08:49:11Z johnnyw $
 *
 *  @author Douglas C. Schmidt
 */
//=============================================================================


#ifndef _PROTOCOL_RECORD_H
#define _PROTOCOL_RECORD_H

#include "Drwho_Node.h"

/**
 * @class Protocol_Record
 *
 * @brief Stores information about a single friend's status.
 */
class Protocol_Record
{

public:
  Protocol_Record (void);
  Protocol_Record (int use_dummy);
  Protocol_Record (const char *key_name1,
                   Protocol_Record *next = 0);
  ~Protocol_Record (void);
  const char *get_host (void);
  const char *set_host (const char *str);
  const char *get_login (void);
  const char *set_login (const char *str);
  const char *get_real (void);
  const char *set_real (const char *str);
  Drwho_Node *get_drwho_list (void);

  static Drwho_Node drwho_node_;
  const char *key_name1_;
  const char *key_name2_;
  Drwho_Node *drwho_list_;
  Protocol_Record *next_;
  int is_active_;
};

#endif /* _PROTOCOL_RECORD_H */
