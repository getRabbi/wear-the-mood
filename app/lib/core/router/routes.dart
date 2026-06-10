/// Centralized route paths + names for type-safe navigation and deep links.
/// Add new routes here as features land (CLAUDE.md §3 feature list).
abstract final class AppRoute {
  static const home = '/';
  static const homeName = 'home';
  static const tryon = '/tryon';
  static const tryonName = 'tryon';
  static const wardrobe = '/wardrobe';
  static const wardrobeName = 'wardrobe';
  static const wardrobeAdd = '/wardrobe/add';
  static const wardrobeAddName = 'wardrobeAdd';
  static const outfits = '/outfits';
  static const outfitsName = 'outfits';
  static const outfitsCreate = '/outfits/create';
  static const outfitsCreateName = 'outfitsCreate';
  static const auth = '/auth';
  static const authName = 'auth';
  static const profile = '/profile';
  static const profileName = 'profile';
  static const avatar = '/avatar';
  static const avatarName = 'avatar';
  static const paywall = '/paywall';
  static const paywallName = 'paywall';
}
