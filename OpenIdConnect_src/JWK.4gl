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

#
# Module implementing JSON Web Key specification
#

IMPORT COM
IMPORT XML
IMPORT Util
IMPORT FGL Logs
IMPORT FGL IdPManager

# Google pub certs : https://www.googleapis.com/oauth2/v2/certs

PRIVATE CONSTANT C_DSIG = "dsig"
PRIVATE CONSTANT C_DSIG_NS = "http://www.w3.org/2000/09/xmldsig#"
PRIVATE CONSTANT C_RSA_KEYVALUE = "RSAKeyValue"

TYPE JWKType RECORD
  kty       STRING, # (Key Type)
  use       STRING, # (Public Key Use) Parameter
  key_ops   STRING, # (Key Operations) Parameter
  alg       STRING, # (Algorithm) Parameter
  kid       STRING, # (Key ID) Parameter
  x5u       STRING, # (X.509 URL) Parameter
  x5c       DYNAMIC ARRAY OF STRING, # (X.509 Certificate Chain) Parameter
  x5t       STRING, # (X.509 Certificate SHA-1 Thumbprint) Parameter
  x5t_S256  STRING, # (X.509 Certificate SHA-256 Thumbprint) Parameter
  typ       STRING, # (Type) Header Parameter
  cty       STRING, # (Content Type) Header Parameter
  crit      STRING, # (Critical) Header Parameter
  n         STRING, # RSA modulo
  e         STRING, # RSA exposant
  k         STRING  # Symmetric value 
END RECORD

TYPE JWKSetType RECORD
  keys DYNAMIC ARRAY OF JWKType
END RECORD

#
# Returns the CryptoKey 
#
PUBLIC FUNCTION RetrieveIdpCryptoKey(p_idp,p_key_id)
  DEFINE  p_idp       IdPManager.IdPType
  DEFINE  p_key_id    VARCHAR(255)
  DEFINE  txt         TEXT
  DEFINE  _key        xml.CryptoKey
  DEFINE  _type       VARCHAR(255)
  CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"JWK","RetrieveIdpCertificate",p_key_id)
  LOCATE txt IN MEMORY
  WHENEVER ERROR CONTINUE 
  SELECT TYPE,value
    INTO _type, txt
    FROM fjs_oidc_keys 
    WHERE provider_id = p_idp.ID AND id = p_key_id
  WHENEVER ERROR STOP
  IF sqlca.sqlcode=0 THEN
    LET _key = xml.CryptoKey.Create(_type)
    CALL _key.loadPublicFromString(txt)
  ELSE IF sqlca.sqlcode = 100 THEN
    # Retrieve key from idp URL 
    LET _key = RegisterCryptoKeysFromURL(p_idp.*,p_key_id)
  END IF
  END IF
  FREE TXT
  IF _key IS NULL THEN
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"JWK","RetrieveIdpCertificate",p_key_id||" not found")
  END IF
  RETURN _key
END FUNCTION

FUNCTION RegisterCryptoKeysFromURL(p_idp,p_key_id)
  DEFINE  p_idp       IdPManager.IdPType
  DEFINE  p_key_id    VARCHAR(255)
  DEFINE  req         com.HTTPRequest
  DEFINE  resp        com.HTTPResponse
  DEFINE  jkeys       JWKSetType
  DEFINE  ind         INTEGER
  DEFINE  _key        xml.CryptoKey
  DEFINE  _type       VARCHAR(255)
  DEFINE  _value      STRING
  DEFINE  ret         xml.CryptoKey
  
  # Retrieve certitificates from URL
  TRY
    LET req = com.HTTPRequest.Create(p_idp.jwks_uri)
    CALL req.doRequest()
    LET resp = req.getResponse()
    IF resp.getStatusCode() != 200 THEN
      RETURN NULL
    END IF
  CATCH
    CALL Logs.LOG_EVENT(Logs.C_LOG_DEBUG,"JWK","RegisterCryptoKeysFromURL","ERROR :"||STATUS)  
  END TRY  
  
  # REMOVE all keys from that IDP
  WHENEVER ANY ERROR CONTINUE
  DELETE FROM fjs_oidc_keys WHERE provider_id = p_idp.ID
  WHENEVER ANY ERROR STOP

  # Decode JWKSet
  CALL util.JSON.parse(resp.getTextResponse(),jkeys)

  # Register in global keys
  FOR ind=1 TO jkeys.keys.getLength()
    LET _key = CreateXmlKeyFromJWK(jkeys.keys[ind].*)
    IF jkeys.keys[ind].kid == p_key_id THEN
      LET ret = _key # To be returned
    END IF
    LET _type = _key.getUrl()
    LET _value = _key.savePublicToString()
    INSERT INTO fjs_oidc_keys VALUES (p_idp.ID, jkeys.keys[ind].kid, _type, _value)
  END FOR
  RETURN ret
END FUNCTION

PRIVATE FUNCTION CreateXmlKeyFromJWK(jwk)
  DEFINE  jwk   JWKType
  DEFINE  KEY   xml.CryptoKey
  IF jwk.use.equalsIgnoreCase("SIG") THEN
    IF jwk.kty.equalsIgnoreCase("RSA") THEN
      IF jwk.alg IS NULL THEN # default RSA signature is RS256
        LET KEY = CreateRSAPublicKey(
            "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256",
            BASE64URL2BASE64(jwk.n),
            BASE64URL2BASE64(jwk.e))
      ELSE
        IF jwk.alg.equalsIgnoreCase("RS256") THEN
          LET KEY = CreateRSAPublicKey(
            "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256",
            BASE64URL2BASE64(jwk.n),
            BASE64URL2BASE64(jwk.e))
        ELSE
          CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"JWK","CreateXmlKeyFromJWK","unsupported RSA key algo "||jwk.alg)
        END IF
      END IF
    ELSE IF jwk.kty.equalsIgnoreCase("oct") THEN
      IF jwk.alg IS NULL THEN # default oct signature is HS256
        LET KEY = CreateSymmetricKey(
          "http://www.w3.org/2001/04/xmldsig-more#hmac-sha256",
          BASE64URL2BASE64(jwk.k))
      ELSE
        IF jwk.alg.equalsIgnoreCase("HS256") THEN
          LET KEY = CreateSymmetricKey(
            "http://www.w3.org/2001/04/xmldsig-more#hmac-sha256",
            BASE64URL2BASE64(jwk.k))
        ELSE
          CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"JWK","CreateXmlKeyFromJWK","unsupported symmetric key algo "||jwk.alg)
        END IF
      END IF
    ELSE
      CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"JWK","CreateXmlKeyFromJWK","unsupported key type "||jwk.kty)
    END IF
    END IF
  ELSE
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"JWK","CreateXmlKeyFromJWK","unsupported key signature "||jwk.use)
  END IF
  RETURN key
END FUNCTION

PRIVATE FUNCTION CreateSymmetricKey(keyId,value)
  DEFINE  key   xml.CryptoKey
  DEFINE  keyId,VALUE STRING
  IF VALUE IS NULL THEN
    RETURN NULL
  END IF
  # Create key
  LET key = xml.CryptoKey.Create(keyId)
  IF KEY IS NOT NULL THEN
    CALL key.loadFromString(VALUE)
  END IF  RETURN key
END FUNCTION

PRIVATE FUNCTION CreateRSAPublicKey(keyId,modulus,exposant)
  DEFINE  key   xml.CryptoKey
  DEFINE  doc   xml.DomDocument
  DEFINE  root  xml.DomNode
  DEFINE  node  xml.DomNode
  DEFINE  txt   xml.DomNode
  DEFINE  keyId,modulus,exposant STRING
  IF modulus IS NULL OR exposant IS NULL THEN
    RETURN NULL
  END IF
  LET doc = xml.DomDocument.CreateDocumentNS(C_DSIG,C_RSA_KEYVALUE,C_DSIG_NS)
  LET root = doc.getDocumentElement()
  # Create modulus
  LET node = doc.createElementNS(C_DSIG,"Modulus",C_DSIG_NS)
  LET txt = doc.createTextNode(modulus)
  CALL node.appendChild(txt)
  CALL root.appendChild(node)
  # Create exposant
  LET node = doc.createElementNS(C_DSIG,"Exponent",C_DSIG_NS)
  LET txt = doc.createTextNode(exposant)
  CALL node.appendChild(txt)
  CALL root.appendChild(node)
  # Create key
  LET key = xml.CryptoKey.Create(keyId)
  IF KEY IS NOT NULL THEN
    CALL key.loadPublic(doc)
  END IF
  RETURN key
END FUNCTION
 
