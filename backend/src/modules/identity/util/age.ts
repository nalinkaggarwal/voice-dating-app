// Age gate: reject signup if calculated age < 18, based on dateOfBirth.
// Pure function so it's trivially unit-testable without touching the DB
// or the clock in a fragile way.
export function calculateAge(dateOfBirth: Date, asOf: Date = new Date()): number {
  let age = asOf.getFullYear() - dateOfBirth.getFullYear();
  const monthDiff = asOf.getMonth() - dateOfBirth.getMonth();
  const dayDiff = asOf.getDate() - dateOfBirth.getDate();
  if (monthDiff < 0 || (monthDiff === 0 && dayDiff < 0)) {
    age -= 1;
  }
  return age;
}

export const MINIMUM_AGE = 18;

export function isOldEnough(dateOfBirth: Date, asOf: Date = new Date()): boolean {
  return calculateAge(dateOfBirth, asOf) >= MINIMUM_AGE;
}
