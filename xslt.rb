#
# XSLT processor
#
# Copyright (c) 2001 by Michael Neumann (neumann@s-direktnet.de)
#
# $Id: xslt.rb,v 1.17 2001/08/02 09:52:39 michael Exp $
#

#
# Parameter of XPath extension functions:  context, *args
# Parameter of XSLT  extension functions:  template, context, processor, node, content 
#

require "xpathtree"


#
# override XPath::Context#funcall to allow
# user defined XPath functions
#
module XPath
  class Context
    attr_reader :variables
    alias __old_funcall funcall

    def funcall(name, *args)
      __old_funcall(name, *args)
    rescue XPath::NameError 
      @callback.call( self, name, *args ) unless @callback.nil? 
    end

    def register_callback( b )
      @callback = b
    end

  end # class Context

end # module XPath


module XSLT

XSLT_NS = "http://www.w3.org/1999/XSL/Transform"
RUBY_NS = "http://www.fantasy-coders.de/xslt/ruby"
XSLT_EXT_NS  = "http://www.fantasy-coders.de/xslt/ext"

module Utils
  def get_attr( node, name )
    attr = node.attributes.find { | a | a.qualified_name == name }
    attr ? attr.string_value : nil
  end

  def to_xpath( val, context = nil )
    case val
    when Array
      XPath::XPathNodeSet.new( context, *val )
    when String
      XPath::XPathString.new val
    when Numeric
      XPath::XPathNumber.new Float(val)
    when TrueClass, FalseClass
      val ? XPath::XPathTrue : XPath::XPathFalse
    else
      val
    end
  end

  def to_ruby( val )
    if val.kind_of? XPath::XPathObject
      val.to_ruby
    else
      val
    end
  end

end



# 
# encapsulates parsing and evaluating an attribute of the form attr="{any xpath expr}"
#
class Interpolated_Attribute
  include Utils
  def self.interpolate( attrValue, context )
    self.new( attrValue ).eval( context )
  end

  def initialize( attrValue )
    @arr = attrValue.scan( /([^{]*)([{]([^}]*)[}])?/ ).collect { | str, _, xpath |
      [ str, xpath ? XPath.compile( "string(#{ xpath })" ) : nil ]
    }
  end

  def eval( context )
    str = ""
    @arr.each { | s, xpath |
      str << "#{ s }#{ xpath ? to_ruby( xpath.call( context ) ) : '' }"
    }
    str
  end
end

#
# encapsulates a xsl:sort tag
#
class XSL_Sort
  include Utils

  def initialize( node )
    select    = get_attr( node, "select" ) || "."
    @order    = get_attr( node, "order") || "ascending"
    data_type = get_attr( node, "data-type" ) || "text"

    unless %w(ascending descending).include? @order
      raise "xsl:sort 'order' attribute must be either ascending or descending!" 
    end

    @xpath = case data_type
    when "text"   then XPath.compile( "string(#{ select })" )
    when "number" then XPath.compile( "number(#{ select })" )
    else 
      raise "xsl:sort 'data-type' attribute supports either text or number!" 
    end
  end

  def sort( node_array, context )
    arr = node_array.collect { | node | 
      [ @xpath.call( XPath::Context.new( node, context.node.namespace_decls, context.variables ) ), node ] 
    }

    case @order
    when "ascending"  then arr.sort! { | a, b | a[0] <=> b[0] }
    when "descending" then arr.sort! { | a, b | b[0] <=> a[0] }
    end

    arr.collect { | cmp, node | node }
  end

end

#
# encapsulates a xsl:template tag
#
class Template
  include Utils

  attr_reader :name, :mode, :match, :position

  def initialize( node, position, ext_namespaces = [] )
    @position   = position
    @ext_namespaces = ext_namespaces

    # match
    match = get_attr( node, "match" ) 
    if match != nil
      @match = XPath.compile( match )
    else
      @match = nil
    end

    # name
    @name = get_attr( node, "name" ) 
     
    # mode
    @mode = get_attr( node, "mode" ) 
   
    @content = [] 
    parse_children( node, @content )
  end

  def add( stringOrObject, content )
    if content.last.kind_of? String and stringOrObject.kind_of? String
      content.last << stringOrObject
    else
      content << stringOrObject
    end
  end

  def parse_children( node, content )
    node.children.each { | child | 
      parse_node( child, content ) 
    } 
  end

  def parse_node( node, content )
    case node.node_type
    when :text
      add( node.string_value, content )
    when :element then
      # check if it is a xsl node
      if node.namespace_uri == XSLT_NS
        parse_xsl_tag( node, content )
      elsif @ext_namespaces.include? node.namespace_uri
        parse_ext_tag( node, content )
      else
        add( "<#{node.qualified_name}", content ) 
        node.attributes.each { | attr |
          iattr = Interpolated_Attribute.new( attr.string_value )
          #arr = attr.string_value.scan( /([^{]*)([{]([^}]*)[}])?/ ).collect { | str, _, xpath |
            #  [ str, xpath ? XPath.compile( "string(#{ xpath })" ) : nil ]
          #}

          aProc = proc { | context, processor | 
            str = ""
            str << %{ #{ attr.qualified_name }="}
            str << iattr.eval( context )
            #arr.each { | s, xpath |
            #  str << "#{ s }#{ xpath ? to_ruby( xpath.call( context ) ) : '' }"
            #}
            str << '"'
            str
          }

          add( [ node, aProc ], content )
        }
        add( ">", content )

        parse_children( node, content ) 

        add( "</#{node.qualified_name}>", content )
      end
    end
  end

  def parse_ext_tag( node, content )
    new_content = []
    parse_children( node, new_content )

    aProc = proc { | context, processor | 
      obj = processor.ext_elements[node.namespace_uri] || raise( "extension not defined" )
      obj.send( node.name_localpart.tr("-", "_"), self, context, processor, node, new_content ) 
    }
    add( [node, aProc], content )
  end

  def parse_xsl_tag( node, content )
    case node.name_localpart
    # if -------------------------------------------------
    when "if"
      test  = get_attr( node, "test" ) || raise( "missing test attribute in xsl:if" )
      xpath = XPath.compile( "boolean(#{ test })" )
      new_content = []
      parse_children( node, new_content )

      aProc = proc { | context, processor | 
        xpath.call( context ) ? new_content : nil
      }
      add( [node, aProc], content )
    
    # choose -------------------------------------------------
    when "choose"
      whens = node.children.select { | child |  
        child.node_type == :element and 
        child.namespace_uri == XSLT_NS and 
        child.name_localpart == "when"
      }.collect { | child |
        test  = get_attr( child, "test" ) || raise( "missing test attribute in xsl:when" )
        xpath = XPath.compile( "boolean(#{ test })" )
        new_content = []
        parse_children( child, new_content )
        
        # return:
        [xpath, new_content]
      }

      otherwise = node.children.find { | child |
        child.node_type == :element and 
        child.namespace_uri == XSLT_NS and 
        child.name_localpart == "otherwise"
      }

      if otherwise != nil
        new_content = []
        parse_children( otherwise, new_content )
        
        # return:
        otherwise = [nil, new_content]
      end

      aProc = proc { | context, processor | 
        found = whens.find { | xpath, _ | xpath.call( context ) } || otherwise
        if found
          found[1]
        else
          nil
        end
      }
 
      add( [node, aProc], content )

    # text ----------------------------------------------
    when "text"
      add( node.string_value, content )
    
    # value-of ------------------------------------------
    when "value-of"
      xpath = XPath.compile( get_attr( node, "select" ) || raise( "missing select attribute in xsl:value-of" ) )
      aProc = proc { | context, processor | 
        to_xpath( xpath.call( context ), context ).to_str
      }
      add( [node, aProc], content )
     
    # variable ------------------------------------------
    when "variable"
      name   = get_attr( node, "name" )   || raise( "missing name attribute in xsl:variable" )
      select = get_attr( node, "select" ) || raise( "missing select attribute in xsl:variable" )       
      xpath  = XPath.compile( select )

      aProc = proc { | context, processor | 
        # change variables with this because context.variables points to
        # variables
        context.variables[name] = to_xpath( xpath.call( context ), context )
      }
      add( [node, aProc], content )
     
    # apply-templates -----------------------------------
    when "apply-templates"
      select = get_attr( node, "select" )
      mode   = get_attr( node, "mode" )
      xpath  = select ? XPath.compile( select ) : nil 

      sorts = node.children.select { | child |  
        child.node_type == :element and 
        child.namespace_uri == XSLT_NS and 
        child.name_localpart == "sort"
      }.collect { | child | XSL_Sort.new( child ) }

      aProc = proc { | context, processor |
        chlds = (xpath ? xpath.call( context ) : context.node.children)
        sorts.reverse_each { | sort |
          chlds = sort.sort( chlds, context )
        }
        chlds.each { | n |
          processor.apply_template_for_node( n, context, mode )
        }
        nil
      }

      add( [node, aProc], content )

   # for-each ------------------------------------------
    when "for-each"
      select = get_attr( node, "select" )
      xpath  = select ? XPath.compile( select ) : nil 

      sorts = []
      cont  = [] # other nodes than xsl:sort are compiled and stored here

      node.children.each { | child |  
        if child.node_type == :element and 
        child.namespace_uri == XSLT_NS and 
        child.name_localpart == "sort" then
          sorts << XSL_Sort.new( child )
        else
          parse_node( child, cont )
        end
      }

      aProc = proc { | context, processor |
        chlds = (xpath ? xpath.call( context ) : context.node.children)
        sorts.reverse_each { | sort |
          chlds = sort.sort( chlds, context )
        }
        chlds.each { | n |
          apply( processor, n, cont, context.variables )
        }
        nil
      }

      add( [node, aProc], content )


    # call-template -----------------------------------
    when "call-template"
      name = get_attr( node, "name" )     # substitue { .. }  ???

      aProc = proc { | context, processor |
        templ = processor.template_by_name( name ) || raise( "template '#{ name }' not found" )
        templ.apply( processor, context.node, nil, processor.glob_vars )
        nil
      }

      add( [node, aProc], content )

    else
      raise "unknown xsl tag: #{node.name_localpart}"
    end
  end


  # runtime - methods -----------------------------------------

  def match?( node, context, mode )
    return false if @match.nil? or @mode != mode
    @match.call( context ).include? node
  end

  def apply( processor, node, content = nil, variables = {} )

    (content || @content).each { | obj |
      case obj 
      when String
        processor << obj
      when Array
        nd, procObj = obj

        context = XPath::Context.new( node, nd.namespace_decls, variables )
        processor.install_extensions( context )

        res = procObj.call( context, processor )

        # process return value
        case res
        when String
          processor << res
        when Array
          apply( processor, node, res, variables )
        end

      end
    }
  end

  # self > template: self <=> template = 1 
  def <=>( template )
    cmp = @match.source.size <=> template.match.source.size
    if cmp == 0
      @position < template.position ? 1 : -1 
    else
      cmp 
    end
  end
end

#
# encapsulates a whole xslt stylesheet
#
class Stylesheet
  include Utils

  attr_reader :templates
  attr_reader :ext_elements  # for Template
  attr_accessor :output



  def <<( stringOrReadable )
    output.each { | outp |
      outp << stringOrReadable
    }
  end

  def initialize( stringOrReadable, arguments = [] )
    @pos = 0
    @templates = []
    @ext_functions = {XSLT_EXT_NS => [XsltExtFunctions.new, true] }
    @ext_elements = {RUBY_NS => XsltRubyExt.new, XSLT_EXT_NS => XsltExtElements.new}
    @ext_namespaces = [RUBY_NS, XSLT_EXT_NS] 
    
    #
    # <xsl:param name='' select=''>
    #
    @params = []


    parse_stylesheet( stringOrReadable )
    @output = [$stdout]

    #
    # program arguments => XsltExtFuntions#get_arg( key )
    #
    @args = Hash.new( '' )
    arguments.each { | str | k, v = str.split("="); @args[k] = v } 
  end

  # Extension Classes  ---------------------------------------------
  
  class XsltRubyExt
    def eval( template, context, processor, node, content )
      $XSLT_OUTPUT = ""
      Kernel.eval node.string_value, TOPLEVEL_BINDING
      $XSLT_OUTPUT
    end
  end

  class XsltExtFunctions

    def get_arg( key ) 
      @args[ key ]
    end

  end

  class XsltExtElements
    include Utils
    def apply_external_stylesheet( template, context, processor, node, content )
      stylesheet = get_attr( node, "stylesheet" ) || raise( "no stylesheet attribute given" )
      document   = get_attr( node, "document" ) || raise( "no document attribute given" )
      stylesheet = Interpolated_Attribute.interpolate( stylesheet, context )
      document   = Interpolated_Attribute.interpolate( document, context )

      sh = File.readlines( stylesheet ).to_s
      dc = File.readlines( document ).to_s

      style = XSLT::Stylesheet.new( sh )
      style.output = processor.output 
      style.apply( dc )
      nil
    end

    # node is the XSLT node
    # context is XML document context
    def redirect( template, context, processor, node, content )
      file = get_attr( node, "file" ) || raise( "no file attribute given" )
      file = Interpolated_Attribute.interpolate( file, context )

      f = File.open(file, "w+") 
      old_output = processor.output
      processor.output = [f]
      template.apply( processor, context.node, content, context.variables )
      f.close
      
      processor.output = old_output
      nil
    end

    def output_file( template, context, processor, node, content )
      file = get_attr( node, "file" ) || raise( "no file attribute given" )
      file = Interpolated_Attribute.interpolate( file, context )

      File.readlines( file ).to_s
    end
  end

  private # ---------------------------------------------------------

  def parse_stylesheet( stringOrReadable )
    root = XPath::DataModel::Builder.new.parse( stringOrReadable )

    stylesheet = root.children[0]
    @ext_namespaces |= ( get_attr( stylesheet, "extension-element-prefixes" ) || "" ).split(/\s+/).collect { | prefix |
      stylesheet.namespace_decls[prefix] || raise( "namespace not defined for extension element" )
    }
       
   
    stylesheet.children.each { | node |
      case node.node_type
      when :text
        # ignore
      when :element
        case node.namespace_uri
        when XSLT_NS
          case node.name_localpart
          when 'template'
            @templates << Template.new( node, @pos += 1, @ext_namespaces )
          when 'include'
            href = get_attr( node, "href" ) || raise( "missing attribute 'href' in xsl:include" )
            parse_stylesheet( get_string_from_href( href ) )
          when 'param'
            # name, select
            name   = get_attr( node, "name" )   || raise( "missing attribute 'name' in xsl:param" ) 
            select = get_attr( node, "select" ) || raise( "missing attribute 'select' in xsl:param" ) 
            @params << [name, XPath.compile( select )] 
          end
        when XSLT_EXT_NS 
          case node.name_localpart
          when 'functions'
            prefix   = get_attr( node, "prefix" ) || raise( "missing attribute 'prefix' in lxslt:functions" )
            ns       = node.namespace_decls[prefix] || raise( "missing namespace in lxslt:functions" )
            object   = get_attr( node, "object" )
            convert  = get_attr( node, "convert" ) == "true" ? true : false 

            code = node.string_value
            eval code, TOPLEVEL_BINDING
            obj = eval object, TOPLEVEL_BINDING

            @ext_functions[ns] = [obj, convert] 
          when 'elements'
            prefix   = get_attr( node, "prefix" ) || raise( "missing attribute 'prefix' in lxslt:elements" )
            ns       = node.namespace_decls[prefix] || raise( "missing namespace in lxslt:elements" )
            object   = get_attr( node, "object" )

            code = node.string_value
            eval code, TOPLEVEL_BINDING
            obj = eval object, TOPLEVEL_BINDING

            @ext_elements[ns] = obj
          end
        end
      end
    }

  end

  def get_string_from_href( href )
    File.readlines( href ).to_s
  end

  private # Context -------------------------------------------------

  def fun_callback( context, name, *args )
    ns_prefix, fun_name = name.split(":")
    ns = context.get_namespace(ns_prefix)

    fun_obj, convert = @ext_functions[ns]
    if fun_obj != nil
      args = args.collect { | a | to_ruby(a) } if convert
      res = fun_obj.send(fun_name, context, *args)  
      res = to_xpath(res) if convert
      res
    else
      case ns
      when RUBY_NS
        args = args.collect { | a | to_ruby(a) }
        to_xpath( eval("#{fun_name}( *args )"), context )
      else
        raise "Function not defined"
      end
    end
  end


  public # User functions -------------------------------------------

  def apply( stringOrReadable )
    root    = XPath::DataModel::Builder.new.parse( stringOrReadable )
    context = XPath::Context.new( root, root.namespace_decls )
    @glob_vars = {}

    install_extensions( context ) 

    @params.each { | name, xpath |
      @glob_vars[ name ] = to_xpath( xpath.call( context ) )
      context = XPath::Context.new( root, root.namespace_decls, @glob_vars ) 
      install_extensions( context ) 
    }

    apply_template_for_node( root, context )
  end


  public # Template functions --------------------------------------- 

  def glob_vars
    new = {}
    @glob_vars.each {| k, v | new[k] = v.dup }
    new
  end

  def install_extensions( context )
    context.register_callback( method(:fun_callback).to_proc )
  end

  
  # mode is template:mode attribute
  def apply_template_for_node( node, context, mode = nil )
    # find best matching template for node ...
    matching = @templates.select { | template |
      template.match?( node, context, mode ) 
    }.max 

    # ... and apply it
    matching.apply( self, node, nil, self.glob_vars ) if matching != nil
  end

  def template_by_name( name )
    @templates.find { | template | template.name == name }
  end

end # class Stylesheet

end # module XSLT

if $0 == __FILE__ 

  if ARGV.size < 2
    puts "USAGE: #$0 stylesheet xml-document [ key=value [ ... ] ]"
    puts "  e.g. #$0 style.xsl data.xml"
    exit 1
  end

  stylesheet   = File.readlines( ARGV[0] ).to_s
  xml_document = File.readlines( ARGV[1] ).to_s

 
  stylesheet = XSLT::Stylesheet.new( stylesheet, ARGV[2..-1] || [] )
  stylesheet.apply( xml_document )
end

