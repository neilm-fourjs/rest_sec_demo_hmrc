#
# FOURJS_START_COPYRIGHT(U,2015)
# Property of Four Js*
# (c) Copyright Four Js 2015, 2018. All Rights Reserved.
# * Trademark of Four Js Development Tools Europe Ltd
#   in the United States and elsewhere
#
# Four Js and its suppliers do not warrant or guarantee that these samples
# are accurate and suitable for your purposes. Their inclusion is purely for
# information purposes only.
# FOURJS_END_COPYRIGHT
#

IMPORT com
IMPORT SECURITY
IMPORT FGL Logs

PRIVATE CONSTANT C_VALIDITY = INTERVAL (5) MINUTE TO MINUTE

PRIVATE
TYPE UUIDType VARCHAR(36)

PRIVATE
TYPE ExpirationType DATETIME YEAR TO SECOND

#
# Creates a new relay state,
#  stores it in database
#  and returns associated UUID value
# @param idp  The IdP Entity ID
# @param url The application URL
# @param pub_id The OAuth public client id
# @param sec_id The OAuth secret client id
# @param authz_prg The authorization program (optional)
#
PUBLIC
FUNCTION CreateRelayState(url, sess_uuid)
  DEFINE  url       VARCHAR(255)
  DEFINE  sess_uuid UUIDType
  DEFINE  uuid      UUIDType
  DEFINE  expires   ExpirationType
  CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"RelayState","CreateRelayState",url)
  LET uuid = security.RandomGenerator.CreateUUIDString()
  LET expires = CURRENT + C_VALIDITY
  TRY
    INSERT INTO fjs_oidc_relaystate VALUES (uuid, sess_uuid, url, expires)
    CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"RelayState","CreateRelayState",SFMT("%1 created for session=%2",uuid, sess_uuid))
    RETURN uuid
  CATCH
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"RelayState","CreateRelayState","unable to insert UUID into relay state table")
    RETURN NULL
  END TRY
END FUNCTION


#+
#+ Check whether given UUID exists in relay state
#+  and returns url, and session uuid
#+  or NULL in case of error
#+
PUBLIC
FUNCTION CheckRelayState(p_uuid)
  DEFINE  p_uuid      UUIDType
  DEFINE  now         ExpirationType
  DEFINE  p_url       VARCHAR(255)
  DEFINE  p_sess_uuid UUIDType
  CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"RelayState","CheckRelayState",NULL)
  LET now = CURRENT
  TRY
    SELECT path, session_uuid
      INTO p_url, p_sess_uuid
      FROM fjs_oidc_relaystate
      WHERE uuid = p_uuid AND now <= expires

      DELETE FROM fjs_oidc_relaystate WHERE UUID = p_uuid
      CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"RelayState","CheckRelayState",p_uuid||" found")
      RETURN p_url, p_sess_uuid

  CATCH
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"RelayState","CheckRelayState",p_uuid||" not found")
    RETURN NULL, NULL

  END TRY
END FUNCTION

#
# Cleans all expired tokens
#
PUBLIC
FUNCTION CleanupRelayState()
  DEFINE now  DATETIME YEAR TO SECOND

  LET now = CURRENT

  DELETE FROM fjs_oidc_relaystate
    WHERE expires < now

  CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"RelayState","RelayState","cleanup")

END FUNCTION






