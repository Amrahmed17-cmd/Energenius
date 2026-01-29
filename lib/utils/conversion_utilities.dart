class ConversionUtilities {
  // Energy conversion rates with kWh as the base unit
  static final Map<String, double> energyConversions = {
    'kWh': 1.0,
    'Wh': 1000.0, // 1 kWh = 1000 Wh
    'MJ': 3.6, // 1 kWh = 3.6 MJ
    'Joule': 3600000.0, // 1 kWh = 3,600,000 Joules
    'BTU': 3412.14, // 1 kWh = 3412.14 BTU
  };

  // Currency conversion rates with EGP as the base currency
  static final Map<String, double> currencyRates = {
    'EGP': 1.0,
    'USD': 0.02, // 1 EGP = 0.02 USD
    'EUR': 0.019, // 1 EGP = 0.019 EUR
    'GBP': 0.016, // 1 EGP = 0.016 GBP
    'AED': 0.075, // 1 EGP = 0.075 AED
    'SAR': 0.077, // 1 EGP = 0.077 SAR
  };

  // Currency symbols for formatting
  static final Map<String, String> currencySymbols = {
    'EGP': 'E£',
    'USD': '\$',
    'EUR': '€',
    'GBP': '£',
    'AED': 'د.إ',
    'SAR': '﷼',
  };

  // Convert energy value from one unit to another
  static double convertEnergy(double value, String fromUnit, String toUnit) {
    if (!energyConversions.containsKey(fromUnit) || !energyConversions.containsKey(toUnit)) {
      throw ArgumentError('Invalid energy unit');
    }
    
    // Convert to kWh first (base unit)
    double valueInKWh = value / energyConversions[fromUnit]!;
    
    // Then convert from kWh to target unit
    return valueInKWh * energyConversions[toUnit]!;
  }

  // Convert currency value from one unit to another
  static double convertCurrency(double value, String fromCurrency, String toCurrency) {
    if (!currencyRates.containsKey(fromCurrency) || !currencyRates.containsKey(toCurrency)) {
      throw ArgumentError('Invalid currency');
    }
    
    // Convert to EGP first (base currency)
    double valueInEGP = value / currencyRates[fromCurrency]!;
    
    // Then convert from EGP to target currency
    return valueInEGP * currencyRates[toCurrency]!;
  }

  // Format currency with appropriate symbol
  static String formatCurrency(double value, String currency) {
    String symbol = currencySymbols[currency] ?? currency;
    return '$symbol ${value.toStringAsFixed(2)}';
  }

  // Get a human-friendly description of the energy conversion
  static String getEnergyConversionInfo(String fromUnit, String toUnit) {
    if (!energyConversions.containsKey(fromUnit) || !energyConversions.containsKey(toUnit)) {
      return 'Invalid units';
    }
    
    double conversionRate = energyConversions[toUnit]! / energyConversions[fromUnit]!;
    return '1 $fromUnit = ${conversionRate.toStringAsFixed(6)} $toUnit';
  }

  // Get a human-friendly description of the currency conversion
  static String getCurrencyConversionInfo(String fromCurrency, String toCurrency) {
    if (!currencyRates.containsKey(fromCurrency) || !currencyRates.containsKey(toCurrency)) {
      return 'Invalid currencies';
    }
    
    double conversionRate = currencyRates[toCurrency]! / currencyRates[fromCurrency]!;
    return '1 $fromCurrency = ${conversionRate.toStringAsFixed(6)} $toCurrency';
  }
} 