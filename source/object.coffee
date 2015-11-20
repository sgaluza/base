
class Space.Object

  # Assign given properties to the instance
  constructor: (properties) -> @[key] = value for key, value of properties

  onDependenciesReady: ->
    # Let mixins initialize themselves when dependencies are ready
    callback.call(this) for callback in @_getMixinCallbacks(@constructor)

  _getMixinCallbacks: (Class) ->
    if Class.__super__?
      superMixins = @_getMixinCallbacks(Class.__super__.constructor)
      return _.union(superMixins, Class.__mixinCallbacks__ ? [])
    else
      return Class.__mixinCallbacks__ ? []

  # Extends this class and return a child class with inherited prototype
  # and static properties.
  #
  # There are various ways you can call this method:
  #
  # 1. Space.Object.extend()
  # --------------------------------------------
  # Creates an anonymous child class without extra prototype properties.
  # Basically the same as `class extend Space.Object` in coffeescript
  #
  # 2. Space.Object.extend(className)
  # --------------------------------------------
  # Creates a named child class without extra prototype properties.
  # Basically the same as `class ClassName extend Space.Object` in coffeescript
  #
  # 3. Space.Object.extend({ prop: 'first', … })
  # --------------------------------------------
  # Creates an anonymous child class with extra prototype properties.
  # Same as:
  # class extend Space.Object
  #   prop: 'first'
  #
  # 4. Space.Object.extend(namespace, className)
  # --------------------------------------------
  # Creates a named class which inherits from Space.Object and assigns
  # it to the given namespace object.
  #
  # 5. Space.Object.extend(className, prototype)
  # --------------------------------------------
  # Creates a named class which inherits from Space.Object and extra prototype
  # properties which are assigned to the new class
  #
  # 6. Space.Object.extend(namespace, className, prototype)
  # --------------------------------------------
  # Creates a named class which inherits from Space.Object, has extra prototype
  # properties and is assigned to the given namespace.
  @extend: (args...) ->

    # Defaults
    namespace = {}
    className = '_Class' # Same as coffeescript
    extension = {}

    # Only one param: (extension) ->
    if args.length is 1
      if _.isObject(args[0]) then extension = args[0]
      if _.isString(args[0]) then className = args[0]

    # Two params must be: (namespace, className) OR (className, extension) ->
    if args.length is 2
      if _.isObject(args[0]) and _.isString(args[1])
        namespace = args[0]
        className = args[1]
        extension = {}
      else if _.isString(args[0]) and _.isObject(args[1])
        namespace = {}
        className = args[0]
        extension = args[1]

    # All three params: (namespace, className, extension) ->
    if args.length is 3
      namespace = args[0]
      className = args[1]
      extension = args[2]

    check namespace, Match.OneOf(Match.ObjectIncluding({}), Function)
    check className, String
    check extension, Match.ObjectIncluding({})

    # Assign the optional custom constructor for this class
    Parent = this
    Constructor = extension.Constructor ? -> Parent.apply(this, arguments)
    className = className.substr className.lastIndexOf('.') + 1

    # Create a named constructor for this class so that debugging
    # consoles are displaying the class name nicely.
    Child = new Function('initialize', 'return function ' + className + '() {
      initialize.apply(this, arguments);
    }')(Constructor)

    # Copy the static properties of this class over to the extended
    Child[key] = this[key] for key of this

    # Copy over static class properties defined on the extension
    if extension.statics?
      _.extend Child, extension.statics
      delete extension.statics

    # Extract mixins before they get added to prototype
    mixins = extension.mixin
    delete extension.mixin

    # Extract onExtending callback and avoid adding it to prototype
    onExtendingCallback = extension.onExtending
    delete extension.onExtending

    # Javascript prototypal inheritance "magic"
    Ctor = ->
      @constructor = Child
      return
    Ctor.prototype = Parent.prototype
    Child.prototype = new Ctor()
    Child.__super__ = Parent.prototype

    # Copy the extension over to the class prototype
    Child.prototype[key] = extension[key] for key of extension

    # Apply mixins
    if mixins? then Child.mixin(mixins)

    # Invoke the onExtending callback after everything has been setup
    onExtendingCallback?.call(Child)

    # Add the class to the namespace
    namespace?[className] = Child

    return Child

  @type: (name) -> @toString = this::toString = -> name

  # Create and instance of the class that this method is called on
  # e.g.: Space.Object.create() would return an instance of Space.Object
  @create: ->
    # Use a wrapper class to hand the constructor arguments
    # to the context class that #create was called on
    args = arguments
    Context = this
    wrapper = -> Context.apply this, args
    wrapper extends Context
    new wrapper()

  # Mixin properties and methods to the class prototype and merge
  # properties that are plain objects to support the mixin of configs etc.
  @mixin: (mixins) ->
    if _.isArray(mixins)
      @_applyMixin(mixin) for mixin in mixins
    else
      @_applyMixin(mixins)

  @_applyMixin: (mixin) ->

    # Create a clone so that we can remove properties without affecting the global mixin
    mixin = _.clone mixin

    # Register the onDependenciesReady method of mixins as a initialization callback
    mixinCallback = mixin.onDependenciesReady
    if mixinCallback?
      # A bit ugly but necessary to check that sub classes don't statically
      # inherit mixin callback arrays from their super classes (coffeescript)
      hasInheritedMixins = (
        @__super__? and
        @__super__.constructor.__mixinCallbacks__ is @__mixinCallbacks__
      )
      @__mixinCallbacks__ = [] if hasInheritedMixins or !@__mixinCallbacks__?
      @__mixinCallbacks__.push mixinCallback
      delete mixin.onDependenciesReady

    # Mixin static properties into the host class
    _.extend(this, mixin.statics) if mixin.statics?
    delete mixin.statics

    # Give mixins the chance to do static setup when applied to the host class
    mixin.onMixinApplied?.call this
    delete mixin.onMixinApplied

    # Helper function to check for object literals only
    isPlainObject = (value) ->
      _.isObject(value) and !_.isArray(value) and !_.isFunction(value)

    # Copy over the mixin to the prototype and merge objects
    for key, value of mixin
      if isPlainObject(value) and isPlainObject(@prototype[key])
        _.deepExtend @prototype[key], value
      else
        @prototype[key] ?= value

  @isSubclassOf = (sup) ->
    isSubclass = this.prototype instanceof sup
    isSameClass = this is sup
    return isSubclass || isSameClass
