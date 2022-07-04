#
# FOURJS_START_COPYRIGHT(U,2015)
# Property of Four Js*
# (c) Copyright Four Js 2015, 2022. All Rights Reserved.
# * Trademark of Four Js Development Tools Europe Ltd
#   in the United States and elsewhere
# 
# Four Js and its suppliers do not warrant or guarantee that these samples
# are accurate and suitable for your purposes. Their inclusion is purely for
# information purposes only.
# FOURJS_END_COPYRIGHT
#

#
# Module implementing JSON Web Token specification
#

IMPORT util
IMPORT security
IMPORT xml
IMPORT FGL Utils
IMPORT FGL Logs
IMPORT FGL JWK
IMPORT FGL IdPManager

PUBLIC TYPE JWTHeaderType RECORD
  alg 	STRING, # The "alg" (algorithm) header parameter identifies the cryptographic algorithm used to secure the JWT. A list of reserved alg values is in Table 4. The processing of the "alg" (algorithm) header parameter, if present, requires that the value of the "alg" header parameter MUST be one that is both supported and for which there exists a key for use with that algorithm associated with the issuer of the JWT. This header parameter is REQUIRED.
  typ 	STRING, # The "typ" (type) header parameter is used to declare that this data structure is a JWT. If a "typ" parameter is present, it is RECOMMENDED that its value be "JWT". This header parameter is OPTIONAL.
  jku 	STRING, # The "jku" (JSON Key URL) header parameter is a URL that points to JSON-encoded public key certificates that can be used to validate the signature. The specification for this encoding is TBD. This header parameter is OPTIONAL.
  kid 	STRING, # The "kid" (key ID) header parameter is a hint indicating which specific key owned by the signer should be used to validate the signature. This allows signers to explicitly signal a change of key to recipients. Omitting this parameter is equivalent to setting it to an empty string. The interpretation of the contents of the "kid" parameter is unspecified. This header parameter is OPTIONAL.
  x5u 	STRING, # The "x5u" (X.509 URL) header parameter is a URL that points to an X.509 public key certificate that can be used to validate the signature. This certificate MUST conform to RFC 5280 [RFC5280]. This header parameter is OPTIONAL.
  x5t 	STRING  # The "x5t" (x.509 certificate thumbprint) header parameter provides a base64url encoded SHA-256 thumbprint (a.k.a. digest) of the DER encoding of an X.509 certificate that can be used to match a certificate. This header parameter is OPTIONAL. 
END RECORD

PUBLIC TYPE JWTClaimsType RECORD
  sub STRING,     # Subject
  exp INTEGER,    # Expiration
  nbf INTEGER,    # Not Before
  iat INTEGER,    # Issued At
  iss STRING,     # Issuer
  aud STRING,     # Audience
  prn STRING, 	  # The prn (principal) claim identifies the subject of the JWT. The processing of this claim is generally application specific. The prn value is case sensitive. This claim is OPTIONAL.
  jti STRING,     # (JWT ID) claim provides a unique identifier for the JWT. The identifier value MUST be assigned in a manner that ensures that there is a negligible probability that the same value will be accidentally assigned to a different data object. The jti claim can be used to prevent the JWT from being replayed. The jti value is case sensitive. This claim is OPTIONAL.
  typ STRING,     # The typ (type) claim is used to declare a type for the contents of this JWT Claims Set. The typ value is case sensitive. This claim is OPTIONAL.
  azp STRING,     # Authorized party - the party to which the ID Token was issued.
  at_hash STRING,  # Access Token hash value
  scopes DYNAMIC ARRAY OF STRING
END RECORD

PUBLIC TYPE JWTType RECORD
  HEADER JWTHeaderType,
  claims JWTClaimsType
END RECORD

PRIVATE FUNCTION CheckAlgo(head)
  DEFINE head  JWTHeaderType
  IF head.alg IS NULL THEN
    RETURN FALSE
  END IF
  CASE head.alg
    WHEN "RS256"
      RETURN TRUE
    WHEN "RSA256"
      RETURN TRUE
    WHEN "HS256"
      RETURN TRUE
    OTHERWISE
      RETURN FALSE
  END CASE  
END FUNCTION

PUBLIC    
FUNCTION DecodeAndValidateCompactJWT(idp,str)
  DEFINE  idp       IdPManager.IdPType
  DEFINE  str       STRING
  DEFINE  ind,ind2  INTEGER
  DEFINE  ret       JWTType
  DEFINE  tmp       STRING
  DEFINE  HEADER    STRING
  DEFINE  payload   STRING
  DEFINE  decoded   STRING
  DEFINE  data2Sign STRING
  DEFINE  signature STRING
  DEFINE  KEY       xml.CryptoKey
  
  # Decode JWT Header
  LET ind = str.getIndexOf('.',1)
  IF ind<1 THEN
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"JWT","DecodeAndValidateCompactJWT","Invalid JWT : no header found")
    RETURN ret.*      
  END IF
  
  # Decode Header
  LET header = str.subString(1,ind-1)
  LET tmp = Utils.BASE64URL2BASE64(header)
  LET decoded = Security.base64.ToStringWithCharset(tmp,"UTF-8")
  CALL util.JSON.parse(decoded,ret.HEADER)
  
  # Ensure Genero support token Algo
  IF NOT CheckAlgo(ret.HEADER.*) THEN
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"JWT","DecodeAndValidateCompactJWT","Unsupported algo : "||ret.HEADER.alg)
    INITIALIZE ret TO NULL
    RETURN ret.*      
  END IF
  
  # Decode JWT payload
  LET ind2 = str.getIndexOf('.',ind+1)
  IF ind2<1 THEN
    CALL Logs.LOG_EVENT(Logs.C_LOG_ERROR,"JWT","DecodeAndValidateCompactJWT","Invalid JWT : no payload found")
    INITIALIZE ret TO NULL
    RETURN ret.*      
  END IF

  # Decode payload
  LET payload = str.subString(ind+1,ind2-1)
  LET tmp = Utils.BASE64URL2BASE64(payload)
  LET decoded = Security.base64.ToStringWithCharset(tmp,"UTF-8")
  CALL Util.JSON.parse(decoded,ret.claims)
  
  # Decode Signature (if any)
  LET data2Sign = header || "." || payload
  LET tmp = str.subString(ind2+1,str.getLength())
  LET signature = Utils.BASE64URL2BASE64(tmp)
  
  # Check Signature validity
  LET KEY = JWK.RetrieveIdpCryptoKey(idp.*,ret.HEADER.kid)
  IF KEY IS NOT NULL THEN
    IF xml.Signature.VerifyString(KEY,data2Sign,signature)==1 THEN
      RETURN ret.*
    END IF
  END IF
  
  INITIALIZE ret TO NULL
  RETURN ret.*
END FUNCTION

PUBLIC
FUNCTION ValidateAtHash(token,str)
  DEFINE token  JWTType
  DEFINE str    STRING
  DEFINE res    STRING
  DEFINE toCmp  STRING
  DEFINE d      Security.Digest
  
  CASE token.HEADER.alg.toUpperCase()
    WHEN "RS256"
      LET d = Security.Digest.CreateDigest("SHA256")
    WHEN "HS256"
      LET d = Security.Digest.CreateDigest("SHA256")
    WHEN "RS384"
      LET d = Security.Digest.CreateDigest("SHA384")    
    WHEN "HS384"
      LET d = Security.Digest.CreateDigest("SHA384")    
    WHEN "RS512"
      LET d = Security.Digest.CreateDigest("SHA512")    
    WHEN "HS512"
      LET d = Security.Digest.CreateDigest("SHA512")    
    OTHERWISE
      RETURN FALSE
  END CASE

  CALL d.AddStringData(str)
  # Create Digest of access_token
  LET res = d.DoHexBinaryDigest()
  # Take left-most 128bits = 128/4 = 32
  LET res = res.subString(1,32)
  # Base64 encode if 
  LET res = Security.Base64.FromHexBinary(res)
  # Base64 Url encode it
  LET toCmp = Utils.Base642Base64Url(res)
  # Compare 
  IF token.claims.at_hash.equals(toCmp) THEN
    RETURN TRUE
  END IF
  RETURN FALSE
  
END FUNCTION
  

