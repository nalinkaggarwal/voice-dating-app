import { calculateAge, isOldEnough } from './age.js';

describe('age', () => {
  const asOf = new Date('2026-09-26T00:00:00Z');

  describe('calculateAge', () => {
    it('counts a birthday already passed this year', () => {
      expect(calculateAge(new Date('2000-01-15T00:00:00Z'), asOf)).toBe(26);
    });

    it('does not count a birthday that has not happened yet this year', () => {
      expect(calculateAge(new Date('2000-12-15T00:00:00Z'), asOf)).toBe(25);
    });

    it('counts exactly on the birthday itself', () => {
      expect(calculateAge(new Date('2000-09-26T00:00:00Z'), asOf)).toBe(26);
    });

    it('counts the day before the birthday as one year younger', () => {
      expect(calculateAge(new Date('2000-09-27T00:00:00Z'), asOf)).toBe(25);
    });
  });

  describe('isOldEnough', () => {
    it('is true at exactly 18', () => {
      expect(isOldEnough(new Date('2008-09-26T00:00:00Z'), asOf)).toBe(true);
    });

    it('is false the day before turning 18', () => {
      expect(isOldEnough(new Date('2008-09-27T00:00:00Z'), asOf)).toBe(false);
    });

    it('is true for a clearly-adult date of birth', () => {
      expect(isOldEnough(new Date('1990-01-01T00:00:00Z'), asOf)).toBe(true);
    });
  });
});
