#
# FOURJS_START_COPYRIGHT(U,2017)
# Property of Four Js*
# (c) Copyright Four Js 2017, 2022. All Rights Reserved.
# * Trademark of Four Js Development Tools Europe Ltd
#   in the United States and elsewhere
# 
# Four Js and its suppliers do not warrant or guarantee that these samples
# are accurate and suitable for your purposes. Their inclusion is purely for
# information purposes only.
# FOURJS_END_COPYRIGHT
#

IMPORT com
IMPORT xml
IMPORT security
IMPORT FGL Logs
IMPORT FGL HTTPHelper
IMPORT FGL RelayState
IMPORT FGL OIDConnect
IMPORT FGL IdPManager
IMPORT FGL Utils

PRIVATE
CONSTANT C_SESSION_VALIDITY      = INTERVAL (5) DAY TO DAY # Session validity time
CONSTANT C_INIT_SESSION_VALIDITY = INTERVAL (3) MINUTE TO MINUTE

PUBLIC
TYPE SessionType RECORD
    uuid            VARCHAR(36),
    provider_id     INTEGER,
    url             VARCHAR(255),
    pub_id          VARCHAR(255),
    secret_id       VARCHAR(255),
    scope           VARCHAR(255),
    authz           VARCHAR(255),
    sign_off        VARCHAR(255),
    end_url         VARCHAR(255),
    subject         VARCHAR(255),
    id_token        TEXT,
    session         VARCHAR(255),
    idp_logout_url  VARCHAR(255),
    expires         DATETIME YEAR TO SECOND
END RECORD

TYPE UUIDType VARCHAR(36)


#+
#+ Create Session UUID to follow application life
#+ @return Null in case of error
#+
PUBLIC
FUNCTION CreateUUID(p_idp_id, p_path, p_pub_id, p_sec_id, p_scope, p_authz, p_sign_off, p_end_url, p_logout_url)
  DEFINE ret SessionType

  DEFINE  p_idp_id      INTEGER
  DEFINE  p_path        VARCHAR(255)
  DEFINE  p_pub_id      VARCHAR(255)
  DEFINE  p_sec_id      VARCHAR(255)
  DEFINE  p_scope       VARCHAR(255)
  DEFINE  p_authz       VARCHAR(255)
  DEFINE  p_sign_off    VARCHAR(255)
  DEFINE  p_end_url     VARCHAR(255)
  DEFINE  p_logout_url  VARCHAR(255)

  LET ret.uuid = security.RandomGenerator.CreateUUIDString()
  LET ret.provider_id = p_idp_id
  LET ret.url = p_path
  LET ret.pub_id = p_pub_id
  LET ret.secret_id = p_sec_id
  LET ret.scope = p_scope
  LET ret.authz = p_authz
  LET ret.sign_off = p_sign_off
  LET ret.end_url = p_end_url
  LET ret.idp_logout_url = p_logout_url
  LET ret.expires = CURRENT + C_INIT_SESSION_VALIDITY

  TRY
    INSERT INTO fjs_oidc_session (uuid, provider_id, url ,pub_id, secret_id, scope, authz, sign_off, end_url, idp_logout_url, expires)
    VALUES (ret.uuid, ret.provider_id, ret.url, ret.pub_id, ret.secret_id, ret.scope, ret.authz, ret.sign_off, ret.end_url, ret.idp_logout_url, ret.expires)
    CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"Session","CreateUUID",SFMT("%1 created for path=%2",ret.uuid, ret.url))
  CATCH
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"Session","CreateUUID",SFMT("Error: unable to create UUID for path %1",p_path))
    INITIALIZE ret TO NULL
  END TRY

  RETURN ret.*
  
END FUNCTION

PUBLIC
FUNCTION DeleteUUID(p_uuid UUIDType)
  TRY
    DELETE FROM fjs_oidc_session
      WHERE uuid ==p_uuid

    CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"Session","DeleteUUID",p_uuid)

  CATCH
    CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"Session","DeleteUUID",p_uuid)
  END TRY

END FUNCTION

PUBLIC
FUNCTION RetrieveByUUID(p_uuid UUIDType)
  DEFINE ret SessionType
  DEFINE now DATETIME YEAR TO SECOND
  LET now = CURRENT
  LOCATE ret.id_token IN MEMORY
  CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"Session","RetrieveByUUID",p_uuid)

  TRY
    SELECT *
    INTO ret.*
    FROM fjs_oidc_session
    WHERE uuid = p_uuid AND now <= expires
    CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"Session","RetrieveByUUID",SFMT("%1 found",p_uuid))
  CATCH
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"Session","RetrieveByUUID",SFMT("Error: %1 not found",p_uuid))
    INITIALIZE ret TO NULL
  END TRY

  RETURN ret.*
END FUNCTION



#
# Store session and expiration
# 
PUBLIC
FUNCTION SetUASession(p_uuid, p_ua_session)
  DEFINE p_uuid       UUIDType
  DEFINE p_ua_session VARCHAR(255)
  DEFINE p_expires    DATETIME YEAR TO SECOND

  LET p_expires = CURRENT + C_SESSION_VALIDITY
  TRY
    UPDATE fjs_oidc_session SET
      session = p_ua_session,
      expires = p_expires      
      WHERE uuid = p_uuid
    CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"Session","SetUASession","done")
    RETURN TRUE    
  CATCH
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"Session","SetUASession","Unable to store state")
    RETURN FALSE    
  END TRY
END FUNCTION

#
# Validate session with subject and set expiration date
# 
PUBLIC
FUNCTION DoValidate(p_uuid, p_subject, p_id_token)
  DEFINE p_uuid       UUIDType
  DEFINE p_subject    VARCHAR(255)
  DEFINE p_id_token   STRING
  DEFINE p_id         TEXT
  DEFINE p_expires    DATETIME YEAR TO SECOND

  LOCATE p_id IN MEMORY
  LET p_id = p_id_token

  LET p_expires = CURRENT + C_SESSION_VALIDITY
  TRY
    UPDATE fjs_oidc_session SET
      subject = p_subject,
      id_token = p_id,
      expires = p_expires      
      WHERE uuid = p_uuid
    CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"Session","DoValidate",SFMT("%1 validated",p_uuid))
    RETURN TRUE    
  CATCH
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"Session","DoValidate","Unable to store state")
    RETURN FALSE    
  END TRY
END FUNCTION

#+
#+ Invalidate session
#+
PUBLIC
FUNCTION DoInvalidate(p_uuid UUIDType)

  CALL DeleteUUID(p_uuid)

  CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"Session","DoInvalide",SFMT("%1 invalidated",p_uuid))

END FUNCTION

#+
#+ Invalidate session in 3 minutes
#+  time to log off during query
#+
PUBLIC
FUNCTION DoInvalidateSoon(p_uuid)
  DEFINE p_uuid     UUIDType
  DEFINE p_expires  DATETIME YEAR TO SECOND
  LET p_expires = CURRENT + C_INIT_SESSION_VALIDITY
  TRY
    UPDATE fjs_oidc_session SET
      expires = p_expires
      WHERE uuid = p_uuid
    CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"Session","DoInvalidateSoon",SFMT("%1 validated",p_uuid))
  CATCH
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"Session","DoInvalidateSoon","Unable to store state")
  END TRY

END FUNCTION

#
# Cleans all expired tokens
#

PUBLIC 
FUNCTION CleanupUUID()
  DEFINE now  DATETIME YEAR TO SECOND

  LET now = CURRENT

  WHENEVER ANY ERROR CONTINUE
  DELETE FROM fjs_oidc_session
    WHERE expires < now
  WHENEVER ANY ERROR STOP

  CALL Logs.LOG_EVENT(Logs.C_LOG_MSG,"Session","Session","cleanup")

END FUNCTION



