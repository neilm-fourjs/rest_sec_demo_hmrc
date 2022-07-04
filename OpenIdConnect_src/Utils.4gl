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

IMPORT com
IMPORT security
IMPORT xml
IMPORT FGL WSHelper
  

FUNCTION StartsWith(str,s)
  DEFINE  str   STRING
  DEFINE  s     STRING
  IF str.getIndexOf(s,1)==1 THEN
    RETURN TRUE
  ELSE
    RETURN FALSE
  END IF
END FUNCTION

FUNCTION GetLastIndexOf(str,s)
  DEFINE  str       STRING
  DEFINE  s         STRING
  DEFINE  ind,ind2  INTEGER
  DEFINE  pos       INTEGER 
  LET pos = 0
  FOR ind=1 TO str.getLength()
    LET ind2 = str.getIndexOf(s,ind)
    IF ind2 > pos THEN
      LET pos = ind2
    END IF 
  END FOR 
  RETURN pos
END FUNCTION
  
FUNCTION BuildHTMLSubmit(html, url, queries)
  DEFINE html STRING
  DEFINE url  STRING
  DEFINE queries STRING
  DEFINE query WSHelper.WSQueryType
  DEFINE doc xml.DomDocument
  DEFINE node xml.DomNode
  DEFINE child xml.DomNode
  DEFINE ind INTEGER
  DEFINE ret STRING
  TRY
    LET doc = xml.DomDocument.Create()
    CALL doc.setFeature("auto-id-attribute",TRUE)
    CALL doc.loadFromString(html)
    LET node = doc.getElementById("form")
    CALL node.setAttribute("action",url)
    CALL WSHelper.SplitQueryString(queries) RETURNING query
    FOR ind=1 TO query.getLength()
      LET child = node.appendChildElement("input")
      CALL child.setAttribute("type","hidden")
      CALL child.setAttribute("name",query[ind].name)
      CALL child.setAttribute("value",query[ind].value)
    END FOR
    LET ret = doc.saveToString()
    RETURN ret
  CATCH
    RETURN NULL
  END TRY
END FUNCTION

FUNCTION ReplaceString(str,_name,_value)
  DEFINE  str     STRING
  DEFINE  buf     base.StringBuffer
  DEFINE  ret     STRING 
  DEFINE  _name   STRING
  DEFINE  _value  STRING
  DEFINE  search  STRING
  DEFINE  ind1    INTEGER
  LET search = "$("||_name||")"
  LET ind1 = str.getIndexOf(search,1)
  IF ind1 >1 THEN
    LET buf = base.StringBuffer.create()
    CALL buf.append(str.subString(1,ind1-1))
    CALL buf.append(_value)
    CALL buf.append(str.subString(ind1+search.getLength(),str.getLength()))
    LET ret = buf.toString()
  END IF
  RETURN ret
END FUNCTION

FUNCTION RemoveNewLines(str)
  DEFINE  str   STRING
  DEFINE  buf   base.StringBuffer
  DEFINE  tkz   base.StringTokenizer
  LET buf = base.StringBuffer.create()
  LET tkz = base.StringTokenizer.create(str,"\r\n")
  WHILE (tkz.hasMoreTokens())
    CALL buf.append(tkz.nextToken())
  END WHILE
  RETURN buf.toString()
END FUNCTION


#
# Replaces all text containing $(rep) with val
#
FUNCTION ReplaceXML(node,rep,val)
  DEFINE  node    xml.DomNode
  DEFINE  attr    xml.DomNode
  DEFINE  child   xml.DomNode
  DEFINE  rep     STRING
  DEFINE  val     STRING
  DEFINE  oldtxt  STRING
  DEFINE  newtxt  STRING
  DEFINE  type    STRING
  DEFINE  i       INTEGER
  IF node IS NOT NULL THEN
    LET type = node.getNodeType()
    CASE type
      WHEN "ELEMENT_NODE"
        # Handle attributes
        FOR i=1 TO node.getAttributesCount()
          LET attr = node.getAttributeNodeItem(i)
          CALL ReplaceXML(attr,rep,val)
        END FOR
        LET child = node.getFirstChild()
        WHILE child IS NOT NULL
          CALL ReplaceXML(child,rep,val)
          LET child = child.getNextSibling()
        END WHILE
      WHEN "ATTRIBUTE_NODE"
        LET oldtxt = node.getNodeValue()
        LET newtxt = ReplaceText(oldtxt,rep,val)
        CALL node.setNodeValue(newtxt)
      WHEN "TEXT_NODE"
        LET oldtxt = node.getNodeValue()
        LET newtxt = ReplaceText(oldtxt,rep,val)
        CALL node.setNodeValue(newtxt)
    END CASE
  END IF  
END FUNCTION
  
#
# Replaces in string 'str' the part with $(rep) by 'val'
#
PRIVATE FUNCTION ReplaceText(str,rep,val)
  DEFINE  str   STRING
  DEFINE  rep   STRING
  DEFINE  val   STRING
  DEFINE  ind   INTEGER
  DEFINE  size  INTEGER
  DEFINE  ret   STRING
  DEFINE  tmp   STRING
  LET ind = str.getIndexOf("$("||rep||")",1)
  IF ind<1 THEN
    RETURN str # nothing
  ELSE
    LET size = rep.getLength()+3
  END IF
  IF ind==1 THEN
    LET tmp = str.subString(size+1,str.getLength())
    IF tmp IS NULL THEN
      LET ret = val
    ELSE
      IF val IS NULL THEN
        LET ret = tmp
      ELSE
        LET ret = val || tmp
      END IF
    END IF
  ELSE
    LET tmp = str.subString(ind+size+1,str.getLength())
    IF tmp IS NULL THEN
      IF val IS NULL THEN
        LET ret = str.subString(1,ind-1)
      ELSE
        LET ret = str.subString(1,ind-1) || val 
      END IF
    ELSE
      IF val IS NULL THEN
        LET ret = str.subString(1,ind-1) || tmp
      ELSE
        LET ret = str.subString(1,ind-1) || val || tmp
      END IF
    END IF
  END IF
  RETURN ret
END FUNCTION

FUNCTION format_datetime(dt)
   DEFINE dt DATETIME YEAR TO SECOND
   DEFINE d DATE
   DEFINE s STRING
   LET d = dt
   LET s = (d USING "ddd, dd-mmm-yyyy")
           || " " || EXTEND(dt, HOUR TO SECOND)
   RETURN s
END FUNCTION
   
  
PRIVATE FUNCTION ExtractTextFromDoc(doc,path)
  DEFINE  doc   xml.DomDocument
  DEFINE  path  STRING
  DEFINE  list  xml.DomNodeList
  IF doc IS NOT NULL THEN  
    LET list = doc.selectByXPath(path,NULL)
    IF list.getCount()==1 THEN
      RETURN list.getItem(1)
    END IF
  END IF
  RETURN NULL
END FUNCTION

FUNCTION Base64Url2Base64(s)
  DEFINE  s   STRING
  DEFINE  buf base.stringBuffer
  LET buf = base.StringBuffer.create()
  CALL buf.append(s)
  CALL buf.replace("-","+",0)
  CALL buf.replace("_","/",0)
  CASE (s.getLength() MOD 4)
    WHEN 1
      RETURN NULL # ERROR (Illegal base64url string!)
    WHEN 2
      CALL buf.append("==")
    WHEN 3
      CALL buf.append("=")      
  END CASE
  RETURN buf.toString()
END FUNCTION  

FUNCTION Base642Base64Url(s)
  DEFINE  s   STRING
  DEFINE  buf base.stringBuffer
  LET buf = base.StringBuffer.create()
  CALL buf.append(s)
  CALL buf.replace("+","-",0)
  CALL buf.replace("/","_",0)
  CALL buf.replace("=",NULL,0)
  RETURN buf.toString()
END FUNCTION
